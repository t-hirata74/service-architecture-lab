# Next.js (:3125) ↔ Rails (:3120) のクロスオリジン許可。
# expose に Authorization を入れているのは rodauth が /login / /create-account 成功時に
# Authorization レスポンスヘッダで JWT を返すため (frontend がそれを保存し REST + ?token= WS に使う)。
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(/\Ahttp:\/\/(localhost|127\.0\.0\.1):\d+\z/)

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization]
  end
end
