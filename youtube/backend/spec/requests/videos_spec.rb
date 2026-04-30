require "rails_helper"

RSpec.describe "Videos", type: :request do
  describe "GET /videos" do
    it "returns only published videos newest-first" do
      old_pub = create(:video, :published, title: "old", published_at: 2.days.ago)
      new_pub = create(:video, :published, title: "new", published_at: 1.hour.ago)
      create(:video, :ready, title: "ready - hidden from index")

      get "/videos"

      expect(response).to have_http_status(:ok)
      titles = response.parsed_body["items"].map { _1["title"] }
      expect(titles).to eq([new_pub.title, old_pub.title])
    end
  end

  describe "GET /videos/:id" do
    it "returns the published video detail with author and tags" do
      user  = create(:user, name: "Alice")
      video = create(:video, :published, user: user, title: "公開動画")
      video.tags << create(:tag, name: "rails")

      get "/videos/#{video.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["title"]).to eq("公開動画")
      expect(body["status"]).to eq("published")
      expect(body.dig("author", "name")).to eq("Alice")
      expect(body["tags"]).to include("rails")
    end

    it "404s for transcoding videos (hidden from public)" do
      video = create(:video, :transcoding)
      get "/videos/#{video.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "200s for ready videos (内部確認向け)" do
      video = create(:video, :ready)
      get "/videos/#{video.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /videos/:id/recommendations" do
    let(:base) { AiWorkerClient.base_url }

    it "returns Video records that match worker-scored ids" do
      target = create(:video, :published, title: "target")
      cand1  = create(:video, :published, title: "cand1")
      cand2  = create(:video, :published, title: "cand2")

      stub_request(:post, "#{base}/recommend")
        .to_return(status: 200,
                   body: { target_id: target.id,
                           items: [{ id: cand1.id, score: 0.8 },
                                   { id: cand2.id, score: 0.4 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      get "/videos/#{target.id}/recommendations"

      expect(response).to have_http_status(:ok)
      items = response.parsed_body["items"]
      expect(items.map { _1["id"] }).to eq([cand1.id, cand2.id])
      expect(items.first["score"]).to eq(0.8)
    end

    it "degrades gracefully when ai-worker is unreachable" do
      target = create(:video, :published)
      stub_request(:post, "#{base}/recommend").to_raise(Errno::ECONNREFUSED)

      get "/videos/#{target.id}/recommendations"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("items" => [], "degraded" => true)
    end
  end

  describe "GET /videos/:id/status" do
    it "returns status regardless of viewability" do
      video = create(:video, :transcoding)
      get "/videos/#{video.id}/status"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("transcoding")
    end
  end

  describe "POST /videos/:id/publish" do
    it "transitions ready -> published" do
      video = create(:video, :ready)
      post "/videos/#{video.id}/publish"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("published")
    end

    it "responds 409 from non-ready states" do
      video = create(:video, :transcoding)
      post "/videos/#{video.id}/publish"
      expect(response).to have_http_status(:conflict)
    end
  end
end
