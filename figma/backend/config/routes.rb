Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ActionCable (ADR 0003: dev も Solid Cable / DocumentChannel)。?token=<jwt> で認証。
  mount ActionCable.server => "/cable"

  # rodauth (/create-account /login /logout /change-password ...) は middleware 経由 (ADR 0004)。

  # REST: ロード・作成・catch-up。op の投入/受信は DocumentChannel (ActionCable)。
  resources :documents, only: %i[index create show] do
    member do
      get :operations        # catch-up: ?since=<seq>
      post :auto_layout      # ai-worker proxy (Phase 4-2)
      post :lint             # ai-worker proxy (Phase 4-2)
    end
    resources :members, only: %i[create], controller: "document_members"
  end

  get "me", to: "users#me"
end
