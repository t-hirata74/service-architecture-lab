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

  private

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
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "ai-worker unreachable: #{e.message}"
  end
end
