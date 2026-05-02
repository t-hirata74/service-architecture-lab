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

    # ADR 0004 信頼境界: Rails 側で valid を再計算 (ai-worker の valid フラグは信用しない).
    it "ignores ai-worker's valid flag and recomputes against allowed_source_ids" do
      # ai-worker が source2.id を valid: true で返してきても、Rails 側で
      # allowed_source_ids に無いと判定されれば永続化されない.
      WebMock.reset!
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([
        { chunk_id: 11, source_id: source1.id, snippet: "本文", ord: 0 }
      ])
      stub_synthesize_sse(sse_events([
        { event: "chunk", data: { text: "本文 [#src_#{source2.id}]", ord: 0 } },
        # ai-worker は valid: true と嘘を言う
        { event: "citation", data: { marker: "src_#{source2.id}", source_id: source2.id, chunk_id: 99, position: 3, valid: true } },
        { event: "done", data: { chunks: 1, body_length: 10 } }
      ]))

      described_class.new.run(query)
      # Rails 側で source2 が allowed (= [source1.id, source2.id]) かどうかで再判定.
      # この context の retrieve は source1 のみ → source2 は allowed 外 → 永続化されない
      expect(query.answer.citations.count).to eq(0)
    end
  end

  # ADR 0003: chunk events の ord 順を尊重して body を組み立てる.
  context "chunk events arrive out of order" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 11, source_id: source1.id, snippet: "x", ord: 0 }])
      stub_synthesize_sse(sse_events([
        # 意図的に逆順で送る
        { event: "chunk", data: { text: "[end]", ord: 2 } },
        { event: "chunk", data: { text: "[mid]", ord: 1 } },
        { event: "chunk", data: { text: "[start]", ord: 0 } },
        { event: "done", data: {} }
      ]))
    end

    it "sorts chunks by ord before assembling body" do
      answer = described_class.new.run(query)
      expect(answer.body).to eq("[start][mid][end]")
    end
  end

  # 重複 marker (Citation UNIQUE 制約) の挙動.
  context "duplicate citation events for the same marker" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 11, source_id: source1.id, snippet: "x", ord: 0 }])
      stub_synthesize_sse(sse_events([
        { event: "chunk", data: { text: "[#src_#{source1.id}]", ord: 0 } },
        { event: "citation", data: { marker: "src_#{source1.id}", source_id: source1.id, chunk_id: 11, position: 0, valid: true } },
        { event: "citation", data: { marker: "src_#{source1.id}", source_id: source1.id, chunk_id: 11, position: 0, valid: true } },
        { event: "done", data: {} }
      ]))
    end

    it "persists each marker only once (find_or_create_by)" do
      described_class.new.run(query)
      cits = Citation.where(answer: query.answer)
      expect(cits.count).to eq(1)
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

  context "ai-worker is unreachable on retrieve" do
    before do
      stub_request(:post, "http://localhost:8030/retrieve").to_timeout
    end

    it "raises RetrieveError (subclass of OrchestratorError) and marks query failed" do
      expect { described_class.new.run(query) }.to raise_error(RagOrchestrator::RetrieveError, /unreachable/)
      expect(query.reload).to be_failed
      # mark!(:streaming) は synthesize 直前まで遅延されているので pending → failed の直接遷移
      expect(query.query_retrievals).to be_empty
    end
  end

  context "ai-worker fails on extract" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_request(:post, "http://localhost:8030/extract").to_timeout
    end

    it "raises ExtractError and marks query failed (query_retrievals 残存 = audit)" do
      expect { described_class.new.run(query) }.to raise_error(RagOrchestrator::ExtractError, /unreachable/)
      expect(query.reload).to be_failed
      # query_retrievals は audit として残す (ADR 0001)
      expect(query.query_retrievals.count).to eq(1)
    end
  end

  context "ai-worker fails on synthesize" do
    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 11, source_id: source1.id, snippet: "x", ord: 0 }])
      stub_request(:post, "http://localhost:8030/synthesize/stream").to_timeout
    end

    it "raises SynthesizeError and marks query failed (no answer persisted)" do
      expect { described_class.new.run(query) }.to raise_error(RagOrchestrator::SynthesizeError, /unreachable/)
      expect(query.reload).to be_failed
      expect(query.answer).to be_nil
    end
  end
end
