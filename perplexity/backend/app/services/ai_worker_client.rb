require "net/http"
require "json"

# ADR 0001: Rails ↔ ai-worker は HTTP REST。HTTP クライアント gem (faraday 等) は
# 入れず Net::HTTP で十分 (operating-patterns.md §6 「外部依存の追加判断」と整合)。
class AiWorkerClient
  class Error < StandardError; end

  DEFAULT_BASE_URL = "http://localhost:8030".freeze
  DEFAULT_TIMEOUT = 5.0

  def initialize(base_url: ENV.fetch("AI_WORKER_URL", DEFAULT_BASE_URL), timeout: DEFAULT_TIMEOUT)
    @base_url = base_url
    @timeout = timeout
  end

  # POST /corpus/embed
  # @param texts [Array<String>]
  # @return [Hash{Symbol => Object}] { embeddings: [[Float, ...256], ...], embedding_version: String }
  def corpus_embed(texts)
    raise ArgumentError, "texts must be a non-empty Array" unless texts.is_a?(Array) && !texts.empty?

    body = post_json("/corpus/embed", { texts: texts })
    {
      embeddings: body["embeddings"],
      embedding_version: body["embedding_version"]
    }
  end

  # POST /retrieve (Phase 3 から)
  # @return [Array<Hash>] hits の配列、各要素は { chunk_id:, source_id:, bm25_score:, cosine_score:, fused_score: }
  def retrieve(query_text:, top_k: 10, alpha: 0.5)
    body = post_json("/retrieve", { query_text: query_text, top_k: top_k, alpha: alpha })
    (body["hits"] || []).map do |h|
      {
        chunk_id: h["chunk_id"],
        source_id: h["source_id"],
        bm25_score: h["bm25_score"],
        cosine_score: h["cosine_score"],
        fused_score: h["fused_score"]
      }
    end
  end

  # POST /extract (Phase 3 から)
  def extract(chunk_ids:)
    raise ArgumentError, "chunk_ids must be a non-empty Array" unless chunk_ids.is_a?(Array) && !chunk_ids.empty?

    body = post_json("/extract", { chunk_ids: chunk_ids })
    (body["passages"] || []).map do |p|
      {
        chunk_id: p["chunk_id"],
        source_id: p["source_id"],
        snippet: p["snippet"],
        ord: p["ord"]
      }
    end
  end

  # POST /synthesize/stream (Phase 3 では SSE を **同期で全消費** して event 配列を返す).
  # Phase 4 で SSE proxy に差し替える際は、このメソッドではなく Controller から
  # 直接 chunked stream を読む実装に変える.
  # @return [Array<Hash>] [{ event:, data: }, ...]
  def synthesize_stream(query_text:, passages:, allowed_source_ids:)
    payload = {
      query_text: query_text,
      passages: passages,
      allowed_source_ids: allowed_source_ids
    }
    consume_sse("/synthesize/stream", payload)
  end

  private

  def consume_sse(path, payload)
    uri = URI.parse(@base_url + path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    # SSE は long-lived。Phase 3 の合成は数 chunk なので read_timeout は緩めに
    http.read_timeout = 30.0

    request = Net::HTTP::Post.new(uri.path,
                                  "Content-Type" => "application/json",
                                  "Accept" => "text/event-stream")
    request.body = payload.to_json

    events = []
    http.request(request) do |response|
      raise Error, "ai-worker #{path} returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      buffer = +""
      response.read_body do |chunk|
        buffer << chunk
        # SSE event は \n\n で区切られる
        while (sep_idx = buffer.index("\n\n"))
          block = buffer[0...sep_idx]
          buffer = buffer[(sep_idx + 2)..] || +""
          parsed = parse_sse_block(block)
          events << parsed unless parsed.nil?
        end
      end
    end
    events
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "ai-worker unreachable: #{e.message}"
  end

  def parse_sse_block(block)
    event_name = nil
    data_str = nil
    block.each_line do |raw_line|
      line = raw_line.chomp
      if line.start_with?("event:")
        event_name = line.sub(/^event:\s*/, "")
      elsif line.start_with?("data:")
        # 1 イベント = 1 data: 行 (本プロジェクトの規約)
        data_str = line.sub(/^data:\s*/, "")
      end
      # ":" で始まるコメント行 / 空行は無視
    end
    return nil if event_name.nil? || data_str.nil?

    { event: event_name, data: JSON.parse(data_str) }
  rescue JSON::ParserError => e
    raise Error, "malformed SSE data: #{e.message}"
  end

  def post_json(path, payload)
    uri = URI.parse(@base_url + path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = http.request(request)
    raise Error, "ai-worker #{path} returned #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "ai-worker unreachable: #{e.message}"
  rescue JSON::ParserError => e
    raise Error, "ai-worker returned non-JSON body: #{e.message}"
  end
end
