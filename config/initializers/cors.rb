Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development? || Rails.env.test?
      # Local / Swagger-friendly
      origins "http://localhost:3000", "http://127.0.0.1:3000", "http://0.0.0.0:3000"
    else
      # Production / Sandbox only
      origins "https://api.bonid.ht", "https://sandbox.bonid.ht", "https://your-frontend.com"
    end

    resource "/api/v1/*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true, # optional — for cookies or Authorization headers
      expose: [ "X-Partner-Api-Key", "X-Signature" ],
      max_age: 600
  end
end
