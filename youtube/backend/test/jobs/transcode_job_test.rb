require "test_helper"

class TranscodeJobTest < ActiveJob::TestCase
  setup do
    @video = videos(:transcoding_one)
    @video.update!(status: :transcoding)
  end

  test "marks ready when an original is attached" do
    @video.original.attach(
      io: StringIO.new("fake-bytes"),
      filename: "sample.mp4",
      content_type: "video/mp4"
    )
    TranscodeJob.perform_now(@video.id)
    assert @video.reload.ready?
  end

  test "marks failed when no original attachment" do
    TranscodeJob.perform_now(@video.id)
    assert @video.reload.failed?
  end

  test "noop when video is not transcoding" do
    @video.update!(status: :ready)
    TranscodeJob.perform_now(@video.id)
    assert @video.reload.ready?
  end

  test "noop when video record is missing" do
    assert_nothing_raised { TranscodeJob.perform_now(0) }
  end
end
