Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # ADR 0001: モジュラーモノリス。各 Engine の routes は components/<name>/config/routes.rb で完結。
  mount Core::Engine,      at: "/"
  mount Catalog::Engine,   at: "/"
  mount Inventory::Engine, at: "/"
  mount Orders::Engine,    at: "/"
  mount Apps::Engine,      at: "/apps"
end
