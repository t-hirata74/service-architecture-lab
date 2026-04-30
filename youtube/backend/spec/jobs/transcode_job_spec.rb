require "rails_helper"

RSpec.describe TranscodeJob, type: :job do
  let(:video) { create(:video, :transcoding) }

  it "marks ready when an original is attached" do
    video.original.attach(
      io: StringIO.new("fake-bytes"),
      filename: "sample.mp4",
      content_type: "video/mp4"
    )

    described_class.perform_now(video.id)

    expect(video.reload).to be_ready
  end

  it "marks failed when no original attachment exists" do
    described_class.perform_now(video.id)
    expect(video.reload).to be_failed
  end

  it "is a no-op when video is no longer transcoding" do
    video.update!(status: :ready)
    described_class.perform_now(video.id)
    expect(video.reload).to be_ready
  end

  it "is a no-op when video record is missing" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
