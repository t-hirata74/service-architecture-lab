class HealthController < ApplicationController
  def show
    render json: {
      status: "ok",
      service: "youtube-backend",
      time: Time.current.iso8601
    }
  end
end
