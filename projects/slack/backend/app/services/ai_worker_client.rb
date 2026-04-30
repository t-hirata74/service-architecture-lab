require "net/http"
require "json"

# Slack 風プロジェクトの ai-worker (Python/FastAPI) を呼び出すクライアント。
# Rails ↔ Python の境界はここに集約し、コントローラーから HTTP の詳細を隠蔽する。
class AiWorkerClient
  class Error < StandardError; end

  def initialize(base_url: ENV.fetch("AI_WORKER_URL", "http://localhost:8000"))
    @base_url = base_url
  end

  def summarize(channel_name:, messages:)
    payload = {
      channel_name: channel_name,
      messages: messages.map do |m|
        { id: m.id, user: m.user&.display_name.to_s, body: m.body }
      end,
    }
    post_json("/summarize", payload)
  end

  private

  def post_json(path, payload)
    uri = URI.join(@base_url, path)
    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = JSON.generate(payload)
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 10) do |http|
      http.request(request)
    end
    unless response.code.to_i == 200
      raise Error, "ai-worker #{path}: HTTP #{response.code} #{response.body}"
    end
    JSON.parse(response.body)
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "ai-worker への接続に失敗: #{e.class}: #{e.message}"
  end
end
