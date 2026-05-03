Rails.application.routes.draw do
  # ADR 0007: rodauth-rails (JWT bearer) は middleware として auto-mount される.
  # /login, /logout, /create-account, /change-password, /close-account は middleware 経由.
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
