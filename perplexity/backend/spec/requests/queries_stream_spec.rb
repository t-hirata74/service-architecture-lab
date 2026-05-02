require "rails_helper"

# ADR 0003 / 0005: ActionController::Live (SSE) のテスト.
# transactional fixtures は Live thread と test thread で connection が分離するため
# 効かない (ADR 0005 で予告済み). DatabaseCleaner truncation で代用.
RSpec.describe "GET /queries/:id/stream (SSE)", type: :request do
  self.use_transactional_tests = false

  before(:each) do
    # 各テスト前にクリーン (transactional fixtures の代替)
    [Citation, Answer, QueryRetrieval, Query, Source, User].each(&:delete_all)
  end

  let(:user)   { User.create!(email: "stream-test@example.local") }
  let(:source) { Source.create!(title: "Tower", body: "本文") }
  let(:query)  { user.queries.create!(text: "東京タワー") }

  def headers
    { "X-User-Id" => user.id.to_s }
  end

  def stub_retrieve(hits)
    stub_request(:post, "http://localhost:8030/retrieve")
      .to_return(status: 200, body: { hits: hits, embedding_version: "v1", loaded_chunks: hits.size }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_extract(passages)
    stub_request(:post, "http://localhost:8030/extract")
      .to_return(status: 200, body: { passages: passages }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_synthesize(events_text)
    stub_request(:post, "http://localhost:8030/synthesize/stream")
      .to_return(status: 200, body: events_text,
                 headers: { "Content-Type" => "text/event-stream" })
  end

  def sse(specs)
    specs.map { |s| "event: #{s[:event]}\ndata: #{s[:data].to_json}\n\n" }.join
  end

  def parse_sse(body)
    body.split("\n\n").reject(&:empty?).map do |block|
      event = nil
      data = nil
      block.split("\n").each do |line|
        event = line.sub("event: ", "") if line.start_with?("event: ")
        data = JSON.parse(line.sub("data: ", "")) if line.start_with?("data: ")
      end
      { event: event, data: data }
    end
  end

  context "happy path" do
    before do
      stub_retrieve([
        { chunk_id: 1, source_id: source.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 1, source_id: source.id, snippet: "x", ord: 0 }])
      stub_synthesize(sse([
        { event: "chunk", data: { text: "回答 [#src_#{source.id}]", ord: 0 } },
        { event: "done", data: {} }
      ]))
    end

    it "returns text/event-stream with chunk + citation + done events" do
      get "/queries/#{query.id}/stream", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/event-stream")

      events = parse_sse(response.body)
      names = events.map { |e| e[:event] }
      expect(names).to include("chunk", "citation", "done")
      cit = events.find { |e| e[:event] == "citation" }
      expect(cit[:data]).to include("source_id" => source.id, "valid" => true)

      # 永続化が完了している
      expect(query.reload).to be_completed
      expect(query.answer).to be_present
      expect(query.answer.citations.count).to eq(1)
    end
  end

  context "ai-worker emits out-of-allowed marker (ADR 0004)" do
    before do
      stub_retrieve([
        { chunk_id: 1, source_id: source.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 1, source_id: source.id, snippet: "x", ord: 0 }])
      stub_synthesize(sse([
        { event: "chunk", data: { text: "本文 [#src_999]", ord: 0 } },
        { event: "done", data: {} }
      ]))
    end

    it "emits event:citation_invalid and persists 0 citations" do
      get "/queries/#{query.id}/stream", headers: headers

      events = parse_sse(response.body)
      names = events.map { |e| e[:event] }
      expect(names).to include("citation_invalid")
      expect(names).not_to include("citation")

      expect(query.reload.answer.citations.count).to eq(0)
      expect(query.answer.body).to include("[#src_999]")
    end
  end

  context "graceful degradation §A: retrieve failure (SSE 開始前)" do
    before do
      stub_request(:post, "http://localhost:8030/retrieve").to_timeout
    end

    it "returns 503 with event:error" do
      get "/queries/#{query.id}/stream", headers: headers

      expect(response).to have_http_status(:service_unavailable)
      events = parse_sse(response.body)
      err = events.find { |e| e[:event] == "error" }
      expect(err[:data]).to include("reason" => "ai_worker_unavailable")
      expect(query.reload).to be_failed
    end
  end

  context "graceful degradation §A: 0 hits" do
    before do
      stub_retrieve([])
    end

    it "returns 422 with event:error reason=no_hits" do
      get "/queries/#{query.id}/stream", headers: headers

      expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:unprocessable_content)
      events = parse_sse(response.body)
      err = events.find { |e| e[:event] == "error" }
      expect(err[:data]).to include("reason" => "no_hits")
    end
  end

  context "graceful degradation §B: synthesize failure (SSE 開始後)" do
    before do
      stub_retrieve([
        { chunk_id: 1, source_id: source.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }
      ])
      stub_extract([{ chunk_id: 1, source_id: source.id, snippet: "x", ord: 0 }])
      stub_request(:post, "http://localhost:8030/synthesize/stream").to_timeout
    end

    it "returns 200 (already started) with event:error reason=ai_worker_disconnect" do
      get "/queries/#{query.id}/stream", headers: headers

      expect(response).to have_http_status(:ok)  # SSE 開始後は status を変えられない
      events = parse_sse(response.body)
      err = events.find { |e| e[:event] == "error" }
      expect(err[:data]).to include("reason" => "ai_worker_disconnect")
      expect(query.reload).to be_failed
      expect(query.answer).to be_nil
    end
  end

  context "auth: cannot stream someone else's query" do
    let(:other) { User.create!(email: "other@example.local") }

    it "returns 404" do
      get "/queries/#{query.id}/stream", headers: { "X-User-Id" => other.id.to_s }
      expect(response).to have_http_status(:not_found)
    end
  end

  context "re-streaming a completed query" do
    before do
      query.update!(status: "completed")
      Answer.create!(query: query, body: "既存回答", status: "completed")
    end

    it "returns event:error already_finalized without re-running orchestration" do
      get "/queries/#{query.id}/stream", headers: headers

      events = parse_sse(response.body)
      err = events.find { |e| e[:event] == "error" }
      expect(err[:data]).to include("reason" => "already_finalized")
      expect(WebMock).not_to have_requested(:post, /localhost:8030/)
    end
  end
end
