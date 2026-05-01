require "net/http"

# GET /health
#
# Rails と ai-worker の疎通を 1 エンドポイントで返すサマリ。
# Phase 5 の docker-compose / Terraform で前段 LB の readiness probe として使う想定。
class HealthController < ApplicationController
  AI_WORKER_TIMEOUT = 0.5 # seconds

  def show
    ai = ai_worker_status
    render json: { status: "ok", service: "perplexity-backend", ai_worker: ai }
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
