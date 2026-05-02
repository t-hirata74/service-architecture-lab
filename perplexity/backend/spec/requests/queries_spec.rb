require "rails_helper"

RSpec.describe "Queries API (non-SSE parts)", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" } }

  describe "POST /queries (Phase 4: 即時 201 + stream_url)" do
    context "with valid X-User-Id" do
      it "creates a pending query and returns query_id + stream_url" do
        expect {
          post "/queries", params: { text: "東京タワー" }.to_json, headers: headers
        }.to change(Query, :count).by(1)

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["query_id"]).to eq(Query.last.id)
        expect(body["status"]).to eq("pending")
        expect(body["stream_url"]).to match(%r{/queries/#{Query.last.id}/stream})
      end

      it "does not call ai-worker yet (orchestration starts on /stream)" do
        post "/queries", params: { text: "x" }.to_json, headers: headers
        expect(WebMock).not_to have_requested(:any, /localhost:8030/)
      end
    end

    context "without X-User-Id" do
      it "returns 401" do
        post "/queries", params: { text: "x" }.to_json,
                          headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with unknown X-User-Id" do
      it "returns 401" do
        post "/queries", params: { text: "x" }.to_json,
                          headers: { "X-User-Id" => "999999", "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with non-integer X-User-Id" do
      it "returns 401" do
        post "/queries", params: { text: "x" }.to_json,
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

      it "rejects X-User-Id with 401" do
        post "/queries", params: { text: "x" }.to_json,
                          headers: { "X-User-Id" => user.id.to_s, "Content-Type" => "application/json" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /queries/:id (再描画用)" do
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
