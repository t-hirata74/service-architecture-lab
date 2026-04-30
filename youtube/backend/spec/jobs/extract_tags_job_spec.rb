require "rails_helper"

RSpec.describe ExtractTagsJob, type: :job do
  let(:video) { create(:video, :ready, title: "Rails 入門", description: "tutorial") }
  let(:base)  { AiWorkerClient.base_url }

  it "merges newly extracted tags into the video without removing existing ones" do
    video.tags << create(:tag, name: "manual-tag")

    stub_request(:post, "#{base}/tags/extract")
      .to_return(status: 200, body: { tags: %w[rails tutorial] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    described_class.perform_now(video.id)

    expect(video.reload.tags.pluck(:name).sort).to eq(%w[manual-tag rails tutorial])
  end

  it "swallows AiWorkerClient::Error and logs (no crash)" do
    stub_request(:post, "#{base}/tags/extract").to_raise(Errno::ECONNREFUSED)
    expect { described_class.perform_now(video.id) }.not_to raise_error
    expect(video.reload.tags).to be_empty
  end

  it "does nothing when video is missing" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
