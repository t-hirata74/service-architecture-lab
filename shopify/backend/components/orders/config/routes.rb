Orders::Engine.routes.draw do
  namespace :storefront, defaults: { format: :json } do
    get "cart", to: "carts#show"
    post "cart/items", to: "carts#add_item"
    delete "cart/items/:variant_id", to: "carts#remove_item"

    post "checkout", to: "checkouts#create"
  end
end
