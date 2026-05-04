module Catalog
  # Review fix M8: backend ↔ ai-worker の HTTP クライアント。
  # ローカル完結方針につき LLM 本体は持たず、ai-worker は deterministic な mock を返す。
  # 内部 ingress 認証は X-Internal-Token ヘッダ (perplexity / instagram / reddit と同形式)。
  module AiWorkerClient
    DEFAULT_BASE_URL = "http://127.0.0.1:8070".freeze
    HEADER_INTERNAL = "X-Internal-Token".freeze

    class Error < StandardError; end

    module_function

    def recommend(shop_id:, product_id:, candidate_product_ids:, limit: 5)
      body = { shop_id: shop_id, product_id: product_id, candidate_product_ids: candidate_product_ids, limit: limit }
      post_json("/recommend", body)
    end

    def base_url
      ENV.fetch("AI_WORKER_URL", DEFAULT_BASE_URL)
    end

    def internal_token
      ENV.fetch("AI_WORKER_INTERNAL_TOKEN", "dev-internal-token")
    end

    def post_json(path, body, timeout: 5)
      uri = URI.parse(File.join(base_url, path))
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = timeout
      http.read_timeout = timeout
      req = Net::HTTP::Post.new(uri.request_uri,
                                "Content-Type" => "application/json",
                                HEADER_INTERNAL => internal_token)
      req.body = body.to_json
      res = http.request(req)
      raise Error, "ai-worker #{path} returned #{res.code}" unless res.code.to_i.between?(200, 299)

      JSON.parse(res.body)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "ai-worker unreachable: #{e.class.name}: #{e.message}"
    end
  end
end
