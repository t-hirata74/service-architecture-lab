require "rails_helper"
require "stringio"

RSpec.describe SseProxy do
  let(:proxy) { described_class.new(ai_worker_base: "http://localhost:8030") }
  let(:out) { StringIO.new }

  def stub_ai_synthesize(events_text)
    stub_request(:post, "http://localhost:8030/synthesize/stream")
      .to_return(status: 200, body: events_text, headers: { "Content-Type" => "text/event-stream" })
  end

  def sse(specs)
    specs.map { |s| "event: #{s[:event]}\ndata: #{s[:data].to_json}\n\n" }.join
  end

  def parse_out_events
    out.string.split("\n\n").reject(&:empty?).map do |block|
      event = nil
      data = nil
      block.split("\n").each do |line|
        event = line.sub("event: ", "") if line.start_with?("event: ")
        data = JSON.parse(line.sub("data: ", "")) if line.start_with?("data: ")
      end
      { event: event, data: data }
    end
  end

  context "happy path: chunk events with valid markers" do
    before do
      stub_ai_synthesize(sse([
        { event: "chunk", data: { text: "東京タワーは ", ord: 0 } },
        { event: "chunk", data: { text: "1958 年に [#src_1] 完成した。", ord: 1 } },
        { event: "done",  data: {} }
      ]))
    end

    it "writes event:chunk + event:citation + event:done to the response stream" do
      result = proxy.stream(
        query_text: "Q",
        passages: [],
        allowed_source_ids: [1],
        response_stream: out,
        hits_by_source_id: { 1 => { chunk_id: 11 } }
      )

      events = parse_out_events
      names = events.map { |e| e[:event] }
      expect(names).to include("chunk", "citation", "done")
      # citation event は marker / source_id / chunk_id を持つ
      cit = events.find { |e| e[:event] == "citation" }
      expect(cit[:data]).to include("marker" => "src_1", "source_id" => 1, "chunk_id" => 11, "valid" => true)

      expect(result[:body]).to include("[#src_1]")
      expect(result[:citations].size).to eq(1)
      expect(result[:citations].first[:source_id]).to eq(1)
    end
  end

  context "marker outside allowed_source_ids (ADR 0004)" do
    before do
      stub_ai_synthesize(sse([
        { event: "chunk", data: { text: "本文 [#src_99]", ord: 0 } },
        { event: "done",  data: {} }
      ]))
    end

    it "emits event:citation_invalid (not citation) and does not include in result citations" do
      result = proxy.stream(
        query_text: "Q",
        passages: [],
        allowed_source_ids: [1],  # 99 は allowed 外
        response_stream: out,
        hits_by_source_id: {}
      )

      events = parse_out_events
      names = events.map { |e| e[:event] }
      expect(names).to include("chunk", "citation_invalid", "done")
      expect(names).not_to include("citation")

      invalid = events.find { |e| e[:event] == "citation_invalid" }
      expect(invalid[:data]).to include("marker" => "src_99", "source_id" => 99)

      # 本文には残る (ADR 0004)
      expect(result[:body]).to include("[#src_99]")
      # 永続化対象には含まれない
      expect(result[:citations]).to be_empty
    end
  end

  context "ignores ai-worker citation events (Rails reconstructs from chunks)" do
    before do
      stub_ai_synthesize(sse([
        { event: "chunk", data: { text: "[#src_1]", ord: 0 } },
        # ai-worker が独自に citation event を送ってきても Rails 側は無視
        { event: "citation", data: { marker: "src_999", source_id: 999, position: 0, valid: true } },
        { event: "done", data: {} }
      ]))
    end

    it "uses only the marker found in chunk text, not the ai-worker citation event" do
      result = proxy.stream(
        query_text: "Q",
        passages: [],
        allowed_source_ids: [1],
        response_stream: out,
        hits_by_source_id: { 1 => { chunk_id: 11 } }
      )

      events = parse_out_events
      cit_events = events.select { |e| e[:event] == "citation" }
      expect(cit_events.size).to eq(1)
      expect(cit_events.first[:data]["source_id"]).to eq(1)  # ai-worker の 999 は無視
      expect(result[:citations].first[:source_id]).to eq(1)
    end
  end

  context "marker spans two chunks (partial buffering)" do
    before do
      stub_ai_synthesize(sse([
        { event: "chunk", data: { text: "本文 [#sr", ord: 0 } },
        { event: "chunk", data: { text: "c_1] 続き", ord: 1 } },
        { event: "done",  data: {} }
      ]))
    end

    it "buffers partial marker across chunk boundary and emits a single citation" do
      proxy.stream(
        query_text: "Q",
        passages: [],
        allowed_source_ids: [1],
        response_stream: out,
        hits_by_source_id: { 1 => { chunk_id: 11 } }
      )

      events = parse_out_events
      cits = events.select { |e| e[:event] == "citation" }
      expect(cits.size).to eq(1)
      expect(cits.first[:data]).to include("marker" => "src_1")
    end
  end

  context "ai-worker fails before SSE start" do
    it "raises SseProxy::Error" do
      stub_request(:post, "http://localhost:8030/synthesize/stream")
        .to_return(status: 500, body: "boom")

      expect {
        proxy.stream(query_text: "x", passages: [], allowed_source_ids: [], response_stream: out)
      }.to raise_error(SseProxy::Error, /500/)
    end
  end

  context "ai-worker is unreachable" do
    it "raises SseProxy::Error" do
      stub_request(:post, "http://localhost:8030/synthesize/stream").to_timeout

      expect {
        proxy.stream(query_text: "x", passages: [], allowed_source_ids: [], response_stream: out)
      }.to raise_error(SseProxy::Error, /unreachable/)
    end
  end

  context "stops consuming after done event (no events after done are forwarded)" do
    before do
      stub_ai_synthesize(sse([
        { event: "chunk", data: { text: "a", ord: 0 } },
        { event: "done",  data: {} },
        # done 後に来た event は無視されるべき
        { event: "chunk", data: { text: "ZZZ", ord: 99 } }
      ]))
    end

    it "does not emit events that arrive after done" do
      proxy.stream(query_text: "Q", passages: [], allowed_source_ids: [], response_stream: out)
      expect(out.string).not_to include("ZZZ")
    end
  end
end
