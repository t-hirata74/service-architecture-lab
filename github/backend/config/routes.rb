Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"

  get "/health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check
end
