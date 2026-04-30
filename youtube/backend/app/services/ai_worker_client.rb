# ADR 0003: ai-worker 境界の HTTP クライアント。
# 呼び出し側 (Rails) は失敗時に "AI 機能は欠落するが本流は動く" よう設計する。
# 実 HTTP は Net::HTTP のみ (Slack の AiWorkerClient と同じ方針 / 依存を増やさない)。
require "net/http"
require "json"

class AiWorkerClient
  class Error < StandardError; end
  class Timeout < Error; end

  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 10

  def self.base_url
    ENV.fetch("AI_WORKER_URL", "http://localhost:8010")
  end

  def self.recommend(target:, candidates:, limit: 5)
    payload = {
      target: serialize_video(target),
      candidates: candidates.map { |c| serialize_video(c) },
      limit: limit
    }
    body = post_json("/recommend", payload)
    Array(body["items"])
  end

  def self.extract_tags(title:, description: "")
    body = post_json("/tags/extract", title: title, description: description.to_s)
    Array(body["tags"])
  end

  # サムネは binary を返す (image/png)。失敗時は nil。
  def self.generate_thumbnail(video_id:, title:)
    uri = URI.join(base_url, "/thumbnail")
    http = build_http(uri)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { video_id: video_id, title: title }.to_json
    response = http.request(request)
    return nil unless response.is_a?(Net::HTTPSuccess)
    response.body
  rescue ::Timeout::Error, Errno::ECONNREFUSED, SocketError => e
    Rails.logger.warn("AiWorkerClient.generate_thumbnail failed: #{e.class}: #{e.message}")
    nil
  end

  class << self
    private

    def post_json(path, payload)
      uri = URI.join(base_url, path)
      http = build_http(uri)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
      response = http.request(request)
      raise Error, "ai-worker #{path} HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue ::Timeout::Error => e
      raise Timeout, "ai-worker #{path} timeout: #{e.message}"
    rescue Errno::ECONNREFUSED, SocketError => e
      raise Error, "ai-worker #{path} unreachable: #{e.message}"
    end

    def build_http(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = DEFAULT_OPEN_TIMEOUT
      http.read_timeout = DEFAULT_READ_TIMEOUT
      http.use_ssl = uri.scheme == "https"
      http
    end

    def serialize_video(video)
      {
        id: video.id,
        title: video.title.to_s,
        description: video.description.to_s,
        tags: video.tags.map(&:name)
      }
    end
  end
end
