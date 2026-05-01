require "rails_helper"

RSpec.describe AiWorkerClient do
  let(:client) { described_class.new(base_url: "http://localhost:8030", timeout: 0.5) }

  describe "#corpus_embed" do
    it "POSTs the texts and returns embeddings + version" do
      stub_request(:post, "http://localhost:8030/corpus/embed")
        .with(body: { texts: %w[a b] }.to_json, headers: { "Content-Type" => "application/json" })
        .to_return(
          status: 200,
          body: { embeddings: [[0.1] * 256, [0.2] * 256], embedding_version: "v1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.corpus_embed(%w[a b])
      expect(result[:embedding_version]).to eq("v1")
      expect(result[:embeddings].size).to eq(2)
    end

    it "raises ArgumentError on empty texts" do
      expect { client.corpus_embed([]) }.to raise_error(ArgumentError)
    end

    it "wraps connection refused as Error" do
      stub_request(:post, "http://localhost:8030/corpus/embed").to_raise(Errno::ECONNREFUSED)
      expect { client.corpus_embed(%w[a]) }.to raise_error(AiWorkerClient::Error, /unreachable/)
    end

    it "wraps timeouts as Error" do
      stub_request(:post, "http://localhost:8030/corpus/embed").to_timeout
      expect { client.corpus_embed(%w[a]) }.to raise_error(AiWorkerClient::Error, /unreachable/)
    end

    it "raises Error on 5xx with body context" do
      stub_request(:post, "http://localhost:8030/corpus/embed")
        .to_return(status: 500, body: "boom")
      expect { client.corpus_embed(%w[a]) }.to raise_error(AiWorkerClient::Error, /500.*boom/)
    end

    it "raises Error on 200 with non-JSON body" do
      stub_request(:post, "http://localhost:8030/corpus/embed")
        .to_return(status: 200, body: "<html>not json</html>", headers: { "Content-Type" => "text/html" })
      expect { client.corpus_embed(%w[a]) }.to raise_error(AiWorkerClient::Error, /non-JSON/)
    end
  end
end
