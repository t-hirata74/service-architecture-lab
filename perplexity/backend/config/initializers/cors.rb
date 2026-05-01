Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3035")

    # /queries は POST 作成 / GET 詳細 / X-User-Id ヘッダ受付
    resource "/queries",
             headers: %w[X-User-Id Content-Type],
             methods: %i[get post options]

    # /queries/:id/stream は SSE (fetch ReadableStream + cookie credentials)
    # ADR 0003: SSE proxy 中に X-Accel-Buffering: no を expose
    resource "/queries/*",
             headers: :any,
             methods: %i[get post options],
             credentials: true,
             expose: %w[X-Accel-Buffering]

    resource "/sources/*",
             headers: :any,
             methods: %i[get options]

    resource "/health",
             headers: :any,
             methods: %i[get options]
  end
end
