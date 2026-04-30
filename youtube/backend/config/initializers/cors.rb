# CORS for cross-origin frontend (Next.js on :3015).
# 動画ファイル配信時に Range ヘッダ等を許可するため expose を明示。
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3015")

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[Authorization Content-Range Accept-Ranges],
      max_age: 600
  end
end
