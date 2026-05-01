Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("FRONTEND_ORIGIN", "http://localhost:3025")

    resource "/graphql",
             headers: :any,
             methods: %i[get post options],
             expose: %w[Authorization]

    resource "/health",
             headers: :any,
             methods: %i[get options]

    resource "/internal/*",
             headers: :any,
             methods: %i[post options]
  end
end
