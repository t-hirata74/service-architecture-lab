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

  # ADR 0003 / 0005: SSE パーサのエッジケース regression test.
  # Phase 4 で SSE proxy 化する際にも同じ仕様で動くことを保証する.
  describe "#synthesize_stream (SSE consumer)" do
    let(:base_payload) { { query_text: "x", passages: [], allowed_source_ids: [] } }

    def call
      client.synthesize_stream(**base_payload)
    end

    it "parses well-formed SSE event stream" do
      body = [
        %(event: chunk\ndata: {"text":"a","ord":0}\n\n),
        %(event: done\ndata: {"chunks":1}\n\n)
      ].join
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      events = call
      expect(events.map { |e| e[:event] }).to eq(%w[chunk done])
      expect(events.first[:data]).to eq({ "text" => "a", "ord" => 0 })
    end

    it "joins multi-line data: into a single JSON payload (W3C SSE 仕様)" do
      # SSE 仕様: data: が複数行ある場合は \n で join される.
      # JSON 内の改行は \\n でエスケープされて来る前提なので、line join 後 valid な JSON
      body = %(event: chunk\ndata: {"text":\ndata: "ab","ord":0}\n\n)
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      events = call
      expect(events.size).to eq(1)
      expect(events.first[:data]).to eq({ "text" => "ab", "ord" => 0 })
    end

    it "flushes the last event when trailing \\n\\n is missing" do
      # ai-worker bug or proxy trimming で末尾 \n\n が落ちた場合でも done を取りこぼさない
      body = %(event: chunk\ndata: {"text":"a"}\n\nevent: done\ndata: {"chunks":1}\n)
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      events = call
      expect(events.map { |e| e[:event] }).to eq(%w[chunk done])
    end

    it "ignores keepalive comment lines (\":\" prefix)" do
      body = [
        %(:keepalive\n\n),
        %(event: chunk\ndata: {"text":"a"}\n\n),
        %(:another comment\n\n),
        %(event: done\ndata: {"chunks":1}\n\n)
      ].join
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      events = call
      expect(events.map { |e| e[:event] }).to eq(%w[chunk done])
    end

    it "treats event-less data as default event type \"message\" (W3C SSE 仕様)" do
      body = %(data: {"text":"a"}\n\n)
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      events = call
      expect(events.first[:event]).to eq("message")
      expect(events.first[:data]).to eq({ "text" => "a" })
    end

    it "raises Error on malformed JSON in data" do
      body = %(event: chunk\ndata: not-json\n\n)
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/event-stream" })

      expect { call }.to raise_error(AiWorkerClient::Error, /malformed SSE/)
    end

    it "raises Error on 5xx (header-level failure before stream start)" do
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 500, body: "boom")

      expect { call }.to raise_error(AiWorkerClient::Error, /500.*boom/)
    end

    it "wraps connection failure as Error" do
      stub_request(:post, "http://localhost:8030/synthesize/stream").to_raise(Errno::ECONNREFUSED)
      expect { call }.to raise_error(AiWorkerClient::Error, /unreachable/)
    end
  end
end
