Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ai-worker 疎通含む / Phase 4 で SSE endpoint も追加
  get "health" => "health#show"

  # Phase 4: POST /queries は即時 201 + stream_url を返す。
  # GET /queries/:id/stream で SSE proxy (ActionController::Live).
  # GET /queries/:id は完了後 answer + citations の再描画用.
  resources :queries, only: %i[create show] do
    member { get :stream }
  end
end
