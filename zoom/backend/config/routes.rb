Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :meetings, only: [:create, :show] do
    member do
      post :open      # scheduled → waiting_room
      post :start     # waiting_room → live
      post :join      # current user → waiting participant
      post :admit     # host/co-host が waiting → live に admit (ADR 0002)
      post :leave     # 現 user の退出
      post :end       # live → ended (FinalizeRecordingJob を enqueue)
      post :transfer_host  # ADR 0002: 動的譲渡
      post :retry_summary  # ADR 0003: summarize_failed → 再要約
      get  :summary   # 要約取得
    end
    resources :co_hosts, only: [:create, :destroy], controller: "meeting_co_hosts"
  end
end
