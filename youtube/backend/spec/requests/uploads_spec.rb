require "rails_helper"

RSpec.describe "Uploads", type: :request do
  let(:user) { create(:user, email: "alice@example.test", name: "Alice") }

  let(:fake_mp4) do
    Rack::Test::UploadedFile.new(
      StringIO.new("fake-mp4-bytes"),
      "video/mp4",
      original_filename: "sample.mp4"
    )
  end

  describe "POST /uploads" do
    it "creates an uploaded -> transcoding video and enqueues TranscodeJob" do
      expect {
        post "/uploads", params: {
          user_email: user.email,
          title: "テスト動画",
          description: "Phase 3 アップロードフロー",
          file: fake_mp4
        }
      }.to have_enqueued_job(TranscodeJob)

      expect(response).to have_http_status(:created)
      assert_schema_conform(201)
      body = response.parsed_body
      expect(body["status"]).to eq("transcoding")
      expect(body["original_filename"]).to eq("sample.mp4")

      video = Video.find(body["id"])
      expect(video.original).to be_attached
      expect(video).to be_transcoding
    end

    it "404s when user_email is unknown" do
      post "/uploads", params: {
        user_email: "ghost@nowhere.test",
        title: "x",
        file: fake_mp4
      }
      expect(response).to have_http_status(:not_found)
      assert_schema_conform(404)
    end
  end
end
