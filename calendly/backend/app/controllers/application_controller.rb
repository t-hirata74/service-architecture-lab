class ApplicationController < ActionController::API
  include Pundit::Authorization

  class Unauthorized < StandardError; end

  # ホスト / invitee の public 入力で 422 を返すための共通エラー (review fix C-A-1 / C-A-2)。
  class InvalidParam < StandardError
    attr_reader :param
    def initialize(param, msg = nil)
      @param = param
      super(msg || "invalid parameter: #{param}")
    end
  end

  rescue_from InvalidParam do |e|
    render json: { error: "invalid_param", param: e.param.to_s, message: e.message },
           status: :unprocessable_entity
  end

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

  protected

  # ISO8601 文字列を Time にパース。失敗は 422 (review fix C-A-1)。
  def parse_iso8601!(str, param)
    Time.iso8601(str)
  rescue ArgumentError
    raise InvalidParam.new(param, "must be ISO8601 datetime")
  end

  # IANA tz id / Rails friendly tz name のどちらかを受け入れる (model 側と同形)。
  # ActiveSupport::TimeZone[] は両方を解釈し、不正なら nil を返す。
  def valid_tz_id?(tz)
    ActiveSupport::TimeZone[tz].present?
  end

  private

  def find_current_host!
    account_id = rodauth.session_value
    raise Unauthorized, "invalid or expired JWT" if account_id.nil?

    Host.find_by(id: account_id) || raise(Unauthorized, "host not provisioned")
  end
end
