require "httpx"

# ADR 0003: 内部 trusted ingress (Rails → ai-worker) の薄いクライアント。
# 共有 Bearer トークンで認証する。perplexity / shopify / github と同パターン。
module Internal
  class Client
    class Error < StandardError; end
    class Timeout < Error; end

    DEFAULT_TIMEOUT_SECONDS = 10

    def self.summarize(meeting_id:, recording_id:, transcript_seed:)
      new.summarize(meeting_id:, recording_id:, transcript_seed:)
    end

    def initialize(base_url: ENV.fetch("AI_WORKER_URL", "http://127.0.0.1:8080"),
                   token: ENV.fetch("INTERNAL_INGRESS_TOKEN", "dev-internal-token"),
                   timeout: DEFAULT_TIMEOUT_SECONDS)
      @base_url = base_url
      @token = token
      @timeout = timeout
    end

    def summarize(meeting_id:, recording_id:, transcript_seed:)
      response = HTTPX
        .with(timeout: { request_timeout: @timeout })
        .with(headers: { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" })
        .post(
          "#{@base_url}/summarize",
          body: JSON.dump(
            meeting_id: meeting_id,
            recording_id: recording_id,
            transcript_seed: transcript_seed
          )
        )

      if response.is_a?(HTTPX::ErrorResponse)
        raise Timeout, "ai-worker /summarize failed: #{response.error.message}"
      end
      raise Error, "ai-worker /summarize returned #{response.status}" unless response.status == 200

      JSON.parse(response.body.to_s)
    end
  end
end
