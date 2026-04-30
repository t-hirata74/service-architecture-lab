require "test_helper"

class UploadsApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "POST /uploads creates uploaded -> transcoding video and enqueues job" do
    file = fixture_file_upload("sample.mp4", "video/mp4")

    assert_enqueued_with(job: TranscodeJob) do
      post "/uploads", params: {
        user_email: users(:alice).email,
        title: "テスト動画",
        description: "Phase 3 アップロードフローのテスト",
        file: file
      }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "transcoding", body["status"]
    assert_equal "sample.mp4", body["original_filename"]

    video = Video.find(body["id"])
    assert video.original.attached?
    assert video.transcoding?
  end

  test "GET /videos/:id/status returns status regardless of viewability" do
    video = videos(:transcoding_one)
    get "/videos/#{video.id}/status"
    assert_response :success
    assert_equal "transcoding", JSON.parse(response.body)["status"]
  end

  test "POST /videos/:id/publish transitions ready -> published" do
    video = videos(:ready_one)
    post "/videos/#{video.id}/publish"
    assert_response :success
    assert_equal "published", JSON.parse(response.body)["status"]
  end

  test "POST /videos/:id/publish 409 from non-ready state" do
    video = videos(:transcoding_one)
    post "/videos/#{video.id}/publish"
    assert_response :conflict
  end
end
