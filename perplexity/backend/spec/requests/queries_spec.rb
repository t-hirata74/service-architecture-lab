require "rails_helper"

RSpec.describe "Queries API", type: :request do
  let(:user) { create(:user) }
  let(:source1) { create(:source, title: "Tower") }
  let(:headers) { { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" } }

  def stub_full_pipeline
    stub_request(:post, "http://localhost:8030/retrieve")
      .to_return(status: 200, body: {
        hits: [{ chunk_id: 11, source_id: source1.id, bm25_score: 1.0, cosine_score: 0.0, fused_score: 0.5 }],
        embedding_version: "v1", loaded_chunks: 1
      }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:post, "http://localhost:8030/extract")
      .to_return(status: 200, body: {
        passages: [{ chunk_id: 11, source_id: source1.id, snippet: "本文", ord: 0 }]
      }.to_json, headers: { "Content-Type" => "application/json" })

    sse_body = [
      "event: chunk\ndata: #{ { text: "回答 [#src_#{source1.id}]", ord: 0 }.to_json}\n\n",
      "event: citation\ndata: #{ { marker: "src_#{source1.id}", source_id: source1.id, chunk_id: 11, position: 3, valid: true }.to_json}\n\n",
      "event: done\ndata: #{ { chunks: 1, body_length: 10 }.to_json}\n\n"
    ].join
    stub_request(:post, "http://localhost:8030/synthesize/stream")
      .to_return(status: 200, body: sse_body, headers: { "Content-Type" => "text/event-stream" })
  end

  describe "POST /queries" do
    context "with valid X-User-Id and successful pipeline" do
      before { stub_full_pipeline }

      it "creates the query, runs orchestrator, and returns 201 with answer + citations" do
        post "/queries", params: { text: "東京タワー" }.to_json, headers: headers

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["query"]["status"]).to eq("completed")
        expect(body["answer"]["body"]).to include("[#src_#{source1.id}]")
        expect(body["answer"]["citations"].size).to eq(1)
      end
    end

    context "without X-User-Id" do
      it "returns 401" do
        post "/queries", params: { text: "東京タワー" }.to_json,
                          headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with unknown X-User-Id" do
      it "returns 401" do
        post "/queries",
             params: { text: "東京タワー" }.to_json,
             headers: { "X-User-Id" => "999999", "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with non-integer X-User-Id" do
      it "returns 401 (defensive integer cast)" do
        post "/queries",
             params: { text: "x" }.to_json,
             headers: { "X-User-Id" => "abc", "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "in production environment" do
      around do |example|
        original = Rails.env
        Rails.env = "production"
        example.run
      ensure
        Rails.env = original
      end

      it "rejects X-User-Id with 401 (operating-patterns §7: dev-only auth)" do
        post "/queries",
             params: { text: "x" }.to_json,
             headers: { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when ai-worker /retrieve returns 0 hits" do
      before do
        stub_request(:post, "http://localhost:8030/retrieve")
          .to_return(status: 200, body: {
            hits: [], embedding_version: "v1", loaded_chunks: 0
          }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns 422 no_hits and marks query as failed" do
        post "/queries", params: { text: "x" }.to_json, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to eq("no_hits")
        expect(Query.last).to be_failed
      end
    end

    context "when ai-worker is unreachable" do
      before do
        stub_request(:post, "http://localhost:8030/retrieve").to_timeout
      end

      it "returns 503 ai_worker_unavailable (operating-patterns.md §2 §A)" do
        post "/queries", params: { text: "x" }.to_json, headers: headers
        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)["error"]).to eq("ai_worker_unavailable")
      end
    end
  end

  describe "GET /queries/:id" do
    let!(:query) { create(:query, user: user) }
    let!(:answer) { create(:answer, query: query) }

    it "returns the query with answer + citations for the owner" do
      get "/queries/#{query.id}", headers: { "X-User-Id" => user.id.to_s }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["query"]["id"]).to eq(query.id)
      expect(body["answer"]["body"]).to eq(answer.body)
    end

    it "returns 404 for someone else's query" do
      other = create(:user)
      get "/queries/#{query.id}", headers: { "X-User-Id" => other.id.to_s }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without X-User-Id" do
      get "/queries/#{query.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
