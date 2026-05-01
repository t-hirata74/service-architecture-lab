require "rails_helper"

RSpec.describe "Comments", type: :request do
  let(:user)  { create(:user, email: "alice@example.test", name: "Alice") }
  let(:video) { create(:video, :published) }

  describe "GET /videos/:video_id/comments" do
    it "returns top-level comments with their replies nested" do
      top   = create(:comment, video: video, user: user, body: "first")
      reply = create(:comment, video: video, user: user, parent: top, body: "reply")
      create(:comment, video: video, user: user, body: "second top-level")

      get "/videos/#{video.id}/comments"

      expect(response).to have_http_status(:ok)
      assert_schema_conform(200)
      items = response.parsed_body["items"]
      expect(items.size).to eq(2)
      expect(items[0]["body"]).to eq("first")
      expect(items[0]["replies"].first["id"]).to eq(reply.id)
      expect(items[1]["body"]).to eq("second top-level")
    end

    it "404s when video is not viewable" do
      hidden = create(:video, :transcoding)
      get "/videos/#{hidden.id}/comments"
      expect(response).to have_http_status(:not_found)
      assert_schema_conform(404)
    end
  end

  describe "POST /videos/:video_id/comments" do
    it "creates a top-level comment" do
      post "/videos/#{video.id}/comments",
           params: { user_email: user.email, body: "great video" }

      expect(response).to have_http_status(:created)
      assert_schema_conform(201)
      body = response.parsed_body
      expect(body["body"]).to eq("great video")
      expect(body.dig("author", "name")).to eq("Alice")
    end

    it "creates a reply when parent_id is given" do
      top = create(:comment, video: video, user: user, body: "top")
      post "/videos/#{video.id}/comments",
           params: { user_email: user.email, body: "thanks", parent_id: top.id }

      expect(response).to have_http_status(:created)
      assert_schema_conform(201)
      expect(response.parsed_body["parent_id"]).to eq(top.id)
    end

    it "responds 422 for empty body" do
      post "/videos/#{video.id}/comments",
           params: { user_email: user.email, body: "" }
      expect(response).to have_http_status(:unprocessable_entity)
      assert_schema_conform(422)
    end

    it "responds 404 for unknown user_email" do
      post "/videos/#{video.id}/comments",
           params: { user_email: "ghost@nowhere.test", body: "x" }
      expect(response).to have_http_status(:not_found)
      assert_schema_conform(404)
    end
  end
end
