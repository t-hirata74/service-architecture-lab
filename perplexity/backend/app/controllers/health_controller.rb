require "net/http"

# GET /health
#
# Rails と ai-worker の疎通サマリ。Phase 5 の docker-compose / Terraform で前段 LB の
# readiness probe として使う想定。
#
# operating-patterns.md §2 graceful degradation との整合 (レビュー指摘 §6.2):
#   ai-worker 不通でも HTTP 200 を返す (LB の起動バウンスを避ける) が、トップレベル
#   `status` は "degraded" にする。LB は本流 traffic を流すかどうかをこの値で判断できる.
class HealthController < ApplicationController
  AI_WORKER_TIMEOUT = 0.5 # seconds

  def show
    ai = ai_worker_status
    overall = ai == "ok" ? "ok" : "degraded"
    render json: { status: overall, service: "perplexity-backend", ai_worker: ai }
  end

  private

  def ai_worker_status
    uri = URI.parse("#{ENV.fetch('AI_WORKER_URL', 'http://localhost:8030')}/health")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: AI_WORKER_TIMEOUT, read_timeout: AI_WORKER_TIMEOUT) do |http|
      http.get(uri.path)
    end
    response.is_a?(Net::HTTPSuccess) ? "ok" : "unreachable"
  rescue StandardError
    "unreachable"
  end
end
