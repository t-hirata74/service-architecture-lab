# Phase 5-2 / 5-3: Next.js (:3095) ↔ Rails (:3090) のクロスオリジン許可。
# expose に Authorization を入れているのは rodauth が /login 成功時に Authorization
# レスポンスヘッダで JWT を返すため (frontend がそれを localStorage に保存する)。
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(/\Ahttp:\/\/(localhost|127\.0\.0\.1):\d+\z/)

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization]
  end
end
