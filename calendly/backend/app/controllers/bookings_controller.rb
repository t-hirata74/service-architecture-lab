class BookingsController < ApplicationController
  # ADR 0002: create は public (invitee 認証なし)。host 操作 (index/show/destroy) のみ認証必須。
  before_action :authenticate_host!, except: [ :create ]

  def index
    bookings = policy_scope(Booking).includes(:event_type).order(start_at: :desc).limit(100)
    render json: bookings.map { |b| booking_json(b) }
  end

  def show
    booking = Booking.find(params[:id])
    authorize booking
    render json: booking_json(booking)
  end

  # invitee も叩く。event_type.active が必須。
  def create
    et = EventType.find(params.require(:event_type_id))
    raise ActiveRecord::RecordNotFound unless et.active?

    start_at = parse_iso8601!(params.require(:start_at), :start_at)
    tz_id = params.require(:invitee_tz_id)
    raise InvalidParam.new(:invitee_tz_id, "must be IANA tz id") unless valid_tz_id?(tz_id)

    booking = Bookings::CreateService.new(
      event_type: et,
      start_at: start_at,
      invitee_email: params.require(:invitee_email),
      invitee_name:  params[:invitee_name],
      invitee_tz_id: tz_id
    ).call

    render json: booking_json(booking), status: :created
  end

  # 削除はキャンセル扱い。host のみ可能 (invitee 用 UI は別 ADR で `email + token` トリガに)。
  def destroy
    booking = Booking.find(params[:id])
    authorize booking, :destroy?
    booking.cancel!
    render json: booking_json(booking)
  end

  private

  def booking_json(b)
    {
      id: b.id,
      event_type_id: b.event_type_id,
      host_id: b.host_id,
      start_at: b.start_at.iso8601,
      end_at: b.end_at.iso8601,
      invitee_email: b.invitee_email,
      invitee_name: b.invitee_name,
      invitee_tz_id: b.invitee_tz_id,
      status: b.status
    }
  end
end
