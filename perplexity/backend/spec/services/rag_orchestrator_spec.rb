require "rails_helper"
require "stringio"

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
    specs.map { |spec| "event: #{spec[:event]}\ndata: #{spec[:data].to_json}\n\n" }.join
  end

  # ---- prepare (Phase 4 §A 領域) ----

  describe "#prepare" do
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
      end

      it "persists query_retrievals in rank order and returns Prepared" do
        prepared = described_class.new.prepare(query)
        expect(prepared.hits.size).to eq(2)
        expect(prepared.passages.size).to eq(2)
        expect(prepared.allowed_source_ids).to contain_exactly(source1.id, source2.id)
        expect(prepared.hits_by_source_id[source1.id]).to include(chunk_id: 11)

        retrievals = query.reload.query_retrievals
        expect(retrievals.map(&:rank)).to eq([0, 1])
      end

      it "leaves query.status pending (streaming は stream_to が立てる)" do
        described_class.new.prepare(query)
        expect(query.reload).to be_pending
      end
    end

    context "retrieve returns 0 hits" do
      before { stub_retrieve([]) }

      it "raises NoHitsError and marks query failed" do
        expect { described_class.new.prepare(query) }.to raise_error(RagOrchestrator::NoHitsError)
        expect(query.reload).to be_failed
      end
    end

    context "ai-worker fails on retrieve" do
      before { stub_request(:post, "http://localhost:8030/retrieve").to_timeout }

      it "raises RetrieveError" do
        expect { described_class.new.prepare(query) }.to raise_error(RagOrchestrator::RetrieveError, /unreachable/)
        expect(query.reload).to be_failed
        expect(query.query_retrievals).to be_empty
      end
    end

    context "ai-worker fails on extract" do
      before do
        stub_retrieve([{ chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }])
        stub_request(:post, "http://localhost:8030/extract").to_timeout
      end

      it "raises ExtractError but keeps query_retrievals as audit" do
        expect { described_class.new.prepare(query) }.to raise_error(RagOrchestrator::ExtractError)
        expect(query.reload).to be_failed
        expect(query.query_retrievals.count).to eq(1)
      end
    end
  end

  # ---- stream_to (Phase 4 §B 領域) ----

  describe "#stream_to" do
    let(:out) { StringIO.new }

    before do
      stub_retrieve([
        { chunk_id: 11, source_id: source1.id, bm25_score: 2.0, cosine_score: 0.1, fused_score: 1.0 }
      ])
      stub_extract([{ chunk_id: 11, source_id: source1.id, snippet: "東京タワー本文", ord: 0 }])
    end

    context "happy path" do
      before do
        stub_synthesize_sse(sse_events([
          { event: "chunk", data: { text: "回答 [#src_#{source1.id}]", ord: 0 } },
          { event: "done",  data: {} }
        ]))
      end

      it "transitions query to streaming → completed and persists answer + citations" do
        prepared = described_class.new.prepare(query)
        described_class.new.stream_to(query, prepared, out)

        query.reload
        expect(query).to be_completed
        expect(query.answer.body).to include("[#src_#{source1.id}]")
        expect(query.answer.citations.count).to eq(1)
        expect(query.answer.citations.first.source_id).to eq(source1.id)

        # frontend に流れた event 列に chunk / citation / done が含まれる
        expect(out.string).to include("event: chunk")
        expect(out.string).to include("event: citation")
        expect(out.string).to include("event: done")
      end
    end

    context "ai-worker emits an out-of-allowed marker (ADR 0004)" do
      before do
        # synthesize は source_id=999 (allowed=[source1.id] 外) を吐く
        stub_synthesize_sse(sse_events([
          { event: "chunk", data: { text: "本文 [#src_999] 続き", ord: 0 } },
          { event: "done", data: {} }
        ]))
      end

      it "emits event:citation_invalid to frontend and persists 0 citations" do
        prepared = described_class.new.prepare(query)
        described_class.new.stream_to(query, prepared, out)

        expect(out.string).to include("event: citation_invalid")
        expect(out.string).not_to match(/event: citation\n/)  # event:citation は出ない (citation_invalid はある)
        expect(query.reload.answer.citations.count).to eq(0)
        # 本文には残る (ADR 0004)
        expect(query.answer.body).to include("[#src_999]")
      end
    end

    context "synthesize fails (§B 領域)" do
      before do
        stub_request(:post, "http://localhost:8030/synthesize/stream").to_timeout
      end

      it "raises SynthesizeError and marks query failed (no answer persisted)" do
        prepared = described_class.new.prepare(query)
        expect { described_class.new.stream_to(query, prepared, out) }
          .to raise_error(RagOrchestrator::SynthesizeError, /unreachable/)
        expect(query.reload).to be_failed
        expect(query.answer).to be_nil
      end
    end
  end
end
