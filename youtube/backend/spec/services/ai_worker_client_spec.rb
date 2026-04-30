require "rails_helper"

RSpec.describe AiWorkerClient do
  let(:base) { described_class.base_url }

  describe ".extract_tags" do
    it "returns tag names from the worker response" do
      stub_request(:post, "#{base}/tags/extract")
        .with(body: { title: "Rails 入門", description: "tutorial" }.to_json)
        .to_return(status: 200, body: { tags: %w[rails tutorial] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      tags = described_class.extract_tags(title: "Rails 入門", description: "tutorial")
      expect(tags).to eq(%w[rails tutorial])
    end

    it "raises Error on non-2xx" do
      stub_request(:post, "#{base}/tags/extract")
        .to_return(status: 500, body: "boom")

      expect {
        described_class.extract_tags(title: "x")
      }.to raise_error(AiWorkerClient::Error)
    end

    it "raises Error when worker is unreachable" do
      stub_request(:post, "#{base}/tags/extract").to_raise(Errno::ECONNREFUSED)

      expect {
        described_class.extract_tags(title: "x")
      }.to raise_error(AiWorkerClient::Error)
    end
  end

  describe ".recommend" do
    it "posts target + candidates and returns scored items" do
      target = create(:video, :published, title: "target")
      cand   = create(:video, :published, title: "cand")
      target.tags << create(:tag, name: "rails")
      cand.tags   << target.tags.first

      stub_request(:post, "#{base}/recommend")
        .to_return(status: 200,
                   body: { target_id: target.id,
                           items: [{ id: cand.id, title: "cand", score: 0.5 }] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = described_class.recommend(target: target, candidates: [cand], limit: 5)
      expect(result).to eq([{ "id" => cand.id, "title" => "cand", "score" => 0.5 }])
    end
  end

  describe ".generate_thumbnail" do
    it "returns binary on success" do
      stub_request(:post, "#{base}/thumbnail")
        .to_return(status: 200, body: "PNG-bytes",
                   headers: { "Content-Type" => "image/png" })

      expect(described_class.generate_thumbnail(video_id: 1, title: "x")).to eq("PNG-bytes")
    end

    it "returns nil on failure (graceful degradation)" do
      stub_request(:post, "#{base}/thumbnail").to_raise(Errno::ECONNREFUSED)
      expect(described_class.generate_thumbnail(video_id: 1, title: "x")).to be_nil
    end
  end
end
