require "test_helper"

class VideoStateMachineTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @video = videos(:transcoding_one).tap { |v| v.update!(status: :uploaded) }
  end

  test "start_transcoding! transitions and enqueues job atomically" do
    assert_enqueued_with(job: TranscodeJob, args: [@video.id]) do
      @video.start_transcoding!
    end
    assert @video.reload.transcoding?
  end

  test "start_transcoding! rolls back enqueue if transition fails" do
    @video.update!(status: :ready)
    assert_no_enqueued_jobs only: TranscodeJob do
      assert_raises(Video::InvalidTransition) { @video.start_transcoding! }
    end
    assert @video.reload.ready?, "status should not change on guard failure"
  end

  test "mark_ready! requires transcoding state" do
    @video.update!(status: :uploaded)
    assert_raises(Video::InvalidTransition) { @video.mark_ready! }
  end

  test "publish! requires ready state and stamps published_at" do
    @video.update!(status: :ready, published_at: nil)
    travel_to Time.zone.local(2026, 5, 1, 9) do
      @video.publish!
    end
    assert @video.reload.published?
    assert_equal Time.zone.local(2026, 5, 1, 9).to_i, @video.published_at.to_i
  end

  test "retry_transcoding! moves failed -> transcoding and enqueues" do
    @video.update!(status: :failed)
    assert_enqueued_with(job: TranscodeJob, args: [@video.id]) do
      @video.retry_transcoding!
    end
    assert @video.reload.transcoding?
  end

  test "mark_failed! is allowed from uploaded or transcoding only" do
    @video.update!(status: :ready)
    assert_raises(Video::InvalidTransition) { @video.mark_failed! }
  end
end
