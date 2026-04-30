require "test_helper"

class VideosApiTest < ActionDispatch::IntegrationTest
  test "GET /videos returns only published" do
    get "/videos"
    assert_response :success
    body = JSON.parse(response.body)
    titles = body["items"].map { |v| v["title"] }
    assert_equal ["公開済み動画 2", "公開済み動画 1"], titles
  end

  test "GET /videos/:id returns published video detail" do
    get "/videos/#{videos(:published_one).id}"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "公開済み動画 1", body["title"]
    assert_equal "published", body["status"]
    assert_equal "Alice", body.dig("author", "name")
    assert_includes body["tags"], "rails"
  end

  test "GET /videos/:id 404 for transcoding video" do
    get "/videos/#{videos(:transcoding_one).id}"
    assert_response :not_found
  end

  test "GET /videos/:id 200 for ready video (内部確認向け)" do
    get "/videos/#{videos(:ready_one).id}"
    assert_response :success
  end
end
