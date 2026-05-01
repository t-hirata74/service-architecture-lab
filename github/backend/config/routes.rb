Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"

  namespace :internal do
    post "commit_checks", to: "commit_checks#create"
  end

  get "/health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check
end
