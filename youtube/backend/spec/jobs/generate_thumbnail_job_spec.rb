require "rails_helper"

RSpec.describe GenerateThumbnailJob, type: :job do
  let(:video) { create(:video, :ready, title: "Rails 入門") }
  let(:base)  { AiWorkerClient.base_url }

  it "attaches a thumbnail to the video on success" do
    stub_request(:post, "#{base}/thumbnail")
      .to_return(status: 200, body: "PNG-bytes",
                 headers: { "Content-Type" => "image/png" })

    described_class.perform_now(video.id)

    expect(video.reload.thumbnail).to be_attached
    expect(video.thumbnail.filename.to_s).to eq("video-#{video.id}.png")
  end

  it "skips silently when ai-worker is unreachable" do
    stub_request(:post, "#{base}/thumbnail").to_raise(Errno::ECONNREFUSED)
    described_class.perform_now(video.id)
    expect(video.reload.thumbnail).not_to be_attached
  end
end
