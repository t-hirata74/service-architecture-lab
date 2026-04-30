Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ADR 0001: ActionCable のマウント (API モードでは明示的に必要)
  mount ActionCable.server => "/cable"

  get "me", to: "me#show"

  resources :channels, only: [:index, :create] do
    member do
      post :read
      post :join
    end
    resources :messages, only: [:index, :create]
  end
end
