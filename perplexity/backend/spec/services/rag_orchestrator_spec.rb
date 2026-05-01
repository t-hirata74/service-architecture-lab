require "rails_helper"

RSpec.describe RagOrchestrator do
  let(:user) { create(:user) }
  let(:source1) { create(:source, title: "Tower") }
  let(:source2) { create(:source, title: "RAG") }
  let(:query)   { create(:query, user: user, text: "東京タワー") }

  def stub_retrieve(hits)
    stub_request(:post, "http://localhost:8030/retrieve")
      .to_return(
        status: 200,
        body: { hits: hits, embedding_version: "v1", loaded_chunks: hits.size }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_extract(passages)
    stub_request(:post, "http://localhost:8030/extract")
      .to_return(
        status: 200,
        body: { passages: passages }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_synthesize_sse(events_text)
    stub_request(:post, "http://localhost:8030/synthesize/stream")
      .to_return(
        status: 200,
        body: events_text,
        headers: { "Content-Type" => "text/event-stream" }
      )
  end

  def sse_events(specs)
    specs.map do |spec|
      "event: #{spec[:event]}\ndata: #{spec[:data].to_json}\n\n"
    end.join
  end

  context "happy path" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 2.0, cosine_score: 0.1, fused_score: 1.0 },
        { chunk_id: 22, source_id: source2.id, bm25_score: 0.5, cosine_score: 0.05, fused_score: 0.3 }
      ])
      stub_extract([
        { chunk_id: 11, source_id: source1.id, snippet: "東京タワー本文", ord: 0 },
        { chunk_id: 22, source_id: source2.id, snippet: "RAG 本文", ord: 1 }
      ])
      stub_synthesize_sse(sse_events([
        { event: "chunk", data: { text: "回答冒頭。", ord: 0 } },
        { event: "chunk", data: { text: "東京タワー本文 [#src_#{source1.id}]", ord: 1 } },
        { event: "citation", data: { marker: "src_#{source1.id}", source_id: source1.id, chunk_id: 11, position: 5, valid: true } },
        { event: "done", data: { chunks: 2, body_length: 30 } }
      ]))
    end

    it "persists query_retrievals in rank order" do
      described_class.new.run(query)
      retrievals = query.reload.query_retrievals.to_a
      expect(retrievals.size).to eq(2)
      expect(retrievals.map(&:rank)).to eq([0, 1])
      expect(retrievals.map(&:chunk_id)).to eq([11, 22])
    end

    it "persists answer with assembled body" do
      answer = described_class.new.run(query)
      expect(answer.body).to include("回答冒頭")
      expect(answer.body).to include("[#src_#{source1.id}]")
      expect(answer).to be_completed
    end

    it "transitions query.status from pending → streaming → completed" do
      expect(query).to be_pending
      described_class.new.run(query)
      expect(query.reload).to be_completed
    end

    it "persists only validated citations (allowed_source_ids only)" do
      described_class.new.run(query)
      cits = Citation.where(answer: query.answer)
      expect(cits.count).to eq(1)
      expect(cits.first.source_id).to eq(source1.id)
      expect(cits.first.marker).to eq("src_#{source1.id}")
    end
  end

  context "ai-worker returns out-of-allowed citation (ADR 0004)" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([
        { chunk_id: 11, source_id: source1.id, snippet: "...", ord: 0 }
      ])
      bogus_id = source2.id  # allowed_source_ids = [source1.id] のみ
      stub_synthesize_sse(sse_events([
        { event: "chunk", data: { text: "本文 [#src_#{bogus_id}]", ord: 0 } },
        { event: "citation", data: { marker: "src_#{bogus_id}", source_id: bogus_id, chunk_id: 99, position: 3, valid: false } },
        { event: "done", data: { chunks: 1, body_length: 10 } }
      ]))
    end

    it "keeps the marker in body but does not persist the citation" do
      answer = described_class.new.run(query)
      expect(answer.body).to include("[#src_#{source2.id}]")  # 本文には残る
      expect(answer.citations.count).to eq(0)  # 永続化はされない
    end
  end

  context "retrieve returns 0 hits" do
    before do
      stub_retrieve([])
    end

    it "marks query as failed and raises NoHitsError" do
      expect { described_class.new.run(query) }.to raise_error(RagOrchestrator::NoHitsError)
      expect(query.reload).to be_failed
    end
  end

  context "ai-worker is unreachable" do
    before do
      stub_request(:post, "http://localhost:8030/retrieve").to_timeout
    end

    it "marks query as failed and wraps error" do
      expect { described_class.new.run(query) }.to raise_error(RagOrchestrator::OrchestratorError, /unreachable/)
      expect(query.reload).to be_failed
    end
  end
end
