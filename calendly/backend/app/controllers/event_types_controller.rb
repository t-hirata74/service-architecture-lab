class EventTypesController < ApplicationController
  before_action :authenticate_host!, except: [ :slots ]

  def index
    types = policy_scope(EventType).includes(:host)
    render json: types.map { |t| event_type_json(t) }
  end

  def create
    et = current_host.event_types.new(event_type_params)
    authorize et
    et.save!
    render json: event_type_json(et), status: :created
  end

  def update
    et = current_host.event_types.find(params[:id])
    authorize et
    et.update!(event_type_params)
    render json: event_type_json(et)
  end

  def destroy
    et = current_host.event_types.find(params[:id])
    authorize et
    et.destroy!
    head :no_content
  end

  # ADR 0001: 公開スロット取得 (invitee 用)。認証不要、event_type.active のみ表示。
  def slots
    et = EventType.find(params[:id])
    raise ActiveRecord::RecordNotFound unless et.active?

    from = parse_time(params[:from], default: Time.current)
    to   = parse_time(params[:to],   default: from + 7.days)
    return render(json: { error: "from must be < to" }, status: :unprocessable_entity) if from >= to

    slots = Availability::SlotsService.new(event_type: et, from: from, to: to).call
    invitee_tz = ActiveSupport::TimeZone[params[:tz] || "UTC"]
    return render(json: { error: "invalid tz" }, status: :unprocessable_entity) if invitee_tz.nil?

    render json: slots.map { |s|
      { start_at_utc: s.start_at.iso8601, end_at_utc: s.end_at.iso8601,
        start_at_local: s.start_at.in_time_zone(invitee_tz).iso8601 }
    }
  end

  private

  def event_type_params
    params.permit(:slug, :title, :duration_minutes, :before_buffer_minutes,
                  :after_buffer_minutes, :min_notice_minutes, :max_advance_days, :active)
  end

  def event_type_json(et)
    {
      id: et.id, host_id: et.host_id, slug: et.slug, title: et.title,
      duration_minutes: et.duration_minutes,
      before_buffer_minutes: et.before_buffer_minutes,
      after_buffer_minutes: et.after_buffer_minutes,
      min_notice_minutes: et.min_notice_minutes,
      max_advance_days: et.max_advance_days,
      active: et.active
    }
  end

  def parse_time(str, default:)
    return default if str.blank?
    Time.iso8601(str)
  rescue ArgumentError
    default
  end
end
