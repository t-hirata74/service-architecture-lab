Catalog::Engine.routes.draw do
  namespace :storefront, defaults: { format: :json } do
    get "products", to: "products#index"
    get "products/:slug", to: "products#show"
    get "products/:slug/recommendations", to: "products#recommendations"
  end
end
