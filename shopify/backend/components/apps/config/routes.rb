Apps::Engine.routes.draw do
  # `mount Apps::Engine, at: "/apps"` で main app から mount される前提。
  # Engine 内では `/api/orders` で定義し、URL としては `/apps/api/orders` になる。
  namespace :api, defaults: { format: :json } do
    get "orders", to: "orders#index"
  end
end
