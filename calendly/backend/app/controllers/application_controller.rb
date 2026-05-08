class ApplicationController < ActionController::API
  include Pundit::Authorization

  class Unauthorized < StandardError; end

  rescue_from Unauthorized do |_e|
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  rescue_from Pundit::NotAuthorizedError do |_e|
    render json: { error: "forbidden" }, status: :forbidden
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: "invalid", message: e.record.errors.full_messages.join(", ") },
           status: :unprocessable_entity
  end

  rescue_from Booking::InvalidTransition do |e|
    render json: { error: "invalid_transition", message: e.message }, status: :unprocessable_entity
  end

  rescue_from Bookings::CreateService::BookingConflict do |e|
    render json: { error: "booking_conflict", message: e.message }, status: :conflict
  end

  def current_host
    @current_host ||= find_current_host!
  end

  # Pundit が `current_user` を見るのでエイリアス公開する (内部の主役は current_host)。
  def current_user
    current_host
  end

  def authenticate_host!
    current_host
  end

  private

  def find_current_host!
    account_id = rodauth.session_value
    raise Unauthorized, "invalid or expired JWT" if account_id.nil?

    Host.find_by(id: account_id) || raise(Unauthorized, "host not provisioned")
  end
end
