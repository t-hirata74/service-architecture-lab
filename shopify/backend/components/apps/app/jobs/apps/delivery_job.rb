module Apps
  # ADR 0004: webhook を受信側 endpoint に POST する worker。
  # 2xx → status=delivered。
  # 5xx / timeout / network error → attempts++、まだ MAX 未満なら status=pending 維持で
  # next_attempt_at を backoff(attempts) 秒後に設定 + 自分を再 enqueue。
  # MAX_ATTEMPTS 到達 → status=failed_permanent。
  # 4xx (クライアント側問題) → 即座に failed_permanent (retry しても無駄)。
  class DeliveryJob < ::ApplicationJob
    queue_as :default

    def perform(delivery_id)
      delivery = WebhookDelivery.find(delivery_id)
      return unless delivery.pending?

      subscription = delivery.subscription
      app = subscription.app_installation.app

      delivery.attempts += 1
      delivery.save!

      response = post_webhook(endpoint: subscription.endpoint, body: delivery.payload,
                              secret: app.secret, delivery_id: delivery.delivery_id, topic: delivery.topic)

      handle_response(delivery, response)
    rescue StandardError => e
      handle_failure(delivery, error: e.message) if delivery
      raise unless delivery
    end

    private

    def post_webhook(endpoint:, body:, secret:, delivery_id:, topic:)
      uri = URI.parse(endpoint)
      headers = {
        "Content-Type" => "application/json",
        Signer::HEADER_HMAC => Signer.sign(secret: secret, body: body),
        Signer::HEADER_DELIVERY_ID => delivery_id,
        Signer::HEADER_TOPIC => topic
      }
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
        req = Net::HTTP::Post.new(uri.request_uri, headers)
        req.body = body
        http.request(req)
      end
    end

    def handle_response(delivery, response)
      code = response.code.to_i
      if code.between?(200, 299)
        delivery.update!(status: :delivered, delivered_at: Time.current, last_error: nil)
      elsif code.between?(400, 499)
        # クライアント側永続エラー: retry しない
        delivery.update!(status: :failed_permanent, last_error: "HTTP #{code} (no retry)")
      else
        handle_failure(delivery, error: "HTTP #{code}")
      end
    end

    def handle_failure(delivery, error:)
      if delivery.attempts >= WebhookDelivery::MAX_ATTEMPTS
        delivery.update!(status: :failed_permanent, last_error: error)
      else
        delivery.update!(
          status: :pending,
          last_error: error,
          next_attempt_at: WebhookDelivery.backoff_seconds(delivery.attempts).seconds.from_now
        )
        DeliveryJob.set(wait: WebhookDelivery.backoff_seconds(delivery.attempts).seconds).perform_later(delivery.id)
      end
    end
  end
end
