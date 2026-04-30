require "test_helper"

class VideoTest < ActiveSupport::TestCase
  test "title is required" do
    video = Video.new(user: users(:alice), status: :uploaded)
    assert_not video.valid?
    assert_includes video.errors[:title], "can't be blank"
  end

  test "status enum exposes named scopes" do
    assert_equal 3, Video.statuses[:published]
    assert videos(:published_one).published?
    assert videos(:transcoding_one).transcoding?
  end

  test "listable scope only returns published, ordered by published_at desc" do
    listable_titles = Video.listable.map(&:title)
    # 4 fixtures: 2 published, 1 ready, 1 transcoding → published 2 件のみ
    assert_equal ["公開済み動画 2", "公開済み動画 1"], listable_titles
  end

  test "viewable scope returns ready and published only" do
    statuses = Video.viewable.map(&:status).sort
    assert_equal %w[published published ready], statuses
  end

  test "publish! transitions ready -> published with timestamp" do
    video = videos(:ready_one)
    assert video.ready?
    travel_to Time.zone.local(2026, 4, 30, 12, 0, 0) do
      video.publish!
    end
    assert video.reload.published?
    assert_equal Time.zone.local(2026, 4, 30, 12, 0, 0).to_i, video.published_at.to_i
  end

  test "publish! raises InvalidTransition for non-ready statuses" do
    video = videos(:transcoding_one)
    assert_raises(Video::InvalidTransition) { video.publish! }
    assert video.reload.transcoding?, "transcoding は publish! で遷移しない"
  end

  test "tags association reads through video_tags" do
    assert_equal %w[rails ruby], videos(:published_one).tags.order(:name).pluck(:name)
  end
end
