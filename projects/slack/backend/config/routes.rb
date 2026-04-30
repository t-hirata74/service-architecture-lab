Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "me", to: "me#show"

  resources :channels, only: [:index, :create] do
    member do
      post :read
    end
    resources :messages, only: [:index, :create]
  end
end
