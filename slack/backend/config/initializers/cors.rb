Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Frontend (Next.js) のデフォルトポート。3001 が他プロジェクトの vite と衝突したため 3005 を採用
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3005")

    resource "*",
      headers: :any,
      expose: ["Authorization"],
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: false
  end
end
