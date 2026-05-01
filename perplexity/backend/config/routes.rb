Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ai-worker 疎通含む / Phase 4 で SSE endpoint も追加
  get "health" => "health#show"

  # Phase 3 以降で resources :queries, only: %i[create show] + member { get :stream } を追加
end
