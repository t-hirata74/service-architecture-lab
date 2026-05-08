Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Phase 4-1: REST API。rodauth は middleware 経由で /login / /create-account を提供する。

  # 認証必須 (host) のリソース。slots だけは公開 (invitee も叩く)。
  resources :event_types, only: [ :index, :create, :update, :destroy ] do
    member do
      get :slots
    end
  end

  resources :availability_rules, only: [ :index, :create, :destroy ]
  resources :busy_periods, only: [ :index, :create, :destroy ]

  # bookings: index/show/cancel は host 認証 / create は public (invitee 含む) — controller 側で出し分け。
  resources :bookings, only: [ :index, :show, :create, :destroy ]

  # 公開 event_type の メタ情報 (slot 取得は /event_types/:id/slots 経由)
  get "public/event_types/:host_id/:slug", to: "public_event_types#show", as: :public_event_type
end
