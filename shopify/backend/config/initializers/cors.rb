# Phase 2 (frontend gif): Next.js (:3085) ↔ Rails (:3090) のクロスオリジン許可。
# X-Shop-Subdomain は ADR 0002 の tenant 解決ヘッダ。Authorization は rodauth JWT。
# expose に "Authorization" を入れているのは rodauth が `/login` 成功時に
# Authorization レスポンスヘッダで JWT を返すため。
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(/\Ahttp:\/\/(localhost|127\.0\.0\.1):\d+\z/)

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization]
  end
end
