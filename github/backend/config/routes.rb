Rails.application.routes.draw do
  match "/graphql", to: "graphql#execute", via: %i[get post]

  namespace :internal do
    post "commit_checks", to: "commit_checks#create"
  end

  get "/health", to: "health#show"
  get "up" => "rails/health#show", as: :rails_health_check
end
