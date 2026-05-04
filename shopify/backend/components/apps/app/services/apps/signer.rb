module Apps
  # ADR 0004: HMAC-SHA256 署名 (Shopify と同じ X-Hmac-Sha256 header 形式)。
  # 鍵は App#secret 単一鍵 / rotation なしを ADR 0004 で明示。
  module Signer
    HEADER_HMAC = "X-Hmac-Sha256".freeze
    HEADER_DELIVERY_ID = "X-Webhook-Delivery-Id".freeze
    HEADER_TOPIC = "X-Webhook-Topic".freeze

    module_function

    def sign(secret:, body:)
      digest = OpenSSL::HMAC.digest("sha256", secret, body)
      Base64.strict_encode64(digest)
    end

    def verify(secret:, body:, signature:)
      expected = sign(secret: secret, body: body)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
    end
  end
end
