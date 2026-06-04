require "httpx"

# ADR 0003 / operating-patterns: 内部 trusted ingress (Rails → ai-worker)。
# X-Internal-Token 共有シークレットで認証する (uber / discord ai-worker と同形)。
# ai-worker 不在 / 遅延 / エラーは graceful degradation で吸収し、canvas 編集自体は止めない
# (degraded: true を載せて空 result を返す)。
class AiWorkerClient
  DEFAULT_TIMEOUT_SECONDS = 3

  class << self
    def auto_layout(objects:, mode: nil)
      post("/auto-layout",
           { objects:, mode: mode.presence || "align-left" },
           degraded_default: { "mode" => mode, "updates" => [] })
    end

    def lint(objects:, grid: nil)
      post("/lint",
           { objects:, grid: (grid.presence || 8).to_i },
           degraded_default: { "issues" => [] })
    end

    private

    def post(path, body, degraded_default:)
      response = HTTPX
        .with(timeout: { request_timeout: DEFAULT_TIMEOUT_SECONDS })
        .with(headers: { "X-Internal-Token" => token, "Content-Type" => "application/json" })
        .post("#{base_url}#{path}", body: JSON.dump(body))

      if response.is_a?(HTTPX::ErrorResponse)
        return degrade(path, degraded_default, response.error.message)
      end
      return degrade(path, degraded_default, "status #{response.status}") unless response.status == 200

      JSON.parse(response.body.to_s)
    rescue StandardError => e
      degrade(path, degraded_default, e.message)
    end

    def degrade(path, default, reason)
      Rails.logger.warn("ai-worker #{path} degraded: #{reason}")
      default.merge("degraded" => true)
    end

    def base_url
      ENV.fetch("AI_WORKER_URL", "http://127.0.0.1:8110")
    end

    def token
      ENV.fetch("AI_INTERNAL_TOKEN", "dev-internal-token")
    end
  end
end
