Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # API バージョニングは採用しない (ADR 0005)。
  get "health" => "health#show"

  resources :videos, only: %i[index show create] do
    member do
      get :status, to: "videos#status"
      post :publish
    end
  end

  # Phase 3: アップロード窓口は別エンドポイント。multipart で受け取り
  # トランザクション内で uploaded → transcoding 遷移 + Solid Queue enqueue (ADR 0001)。
  resources :uploads, only: %i[create]
end
