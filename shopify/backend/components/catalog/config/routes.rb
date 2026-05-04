Catalog::Engine.routes.draw do
  namespace :storefront, defaults: { format: :json } do
    get "products", to: "products#index"
    get "products/:slug", to: "products#show"
  end
end
