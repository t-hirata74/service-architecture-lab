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

    errors = []
    from = parse_iso8601_or_default(params[:from], default: Time.current,    on_error: -> { errors << { param: "from", message: "must be ISO8601 datetime" } })
    to   = parse_iso8601_or_default(params[:to],   default: from + 7.days,   on_error: -> { errors << { param: "to",   message: "must be ISO8601 datetime" } })
    errors << { param: "range", message: "from must be < to" } if from >= to

    tz_str = params[:tz] || "UTC"
    invitee_tz = ActiveSupport::TimeZone[tz_str]
    errors << { param: "tz", message: "must be IANA tz id" } if invitee_tz.nil?

    return render(json: { error: "invalid_param", errors: errors }, status: :unprocessable_entity) if errors.any?

    slots = Availability::SlotsService.new(event_type: et, from: from, to: to).call
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

  # blank はデフォルト値、不正値は on_error を呼んでデフォルト返却 (review fix C-A-2)。
  # silent fallback ではなく caller 側でエラー収集する。
  def parse_iso8601_or_default(str, default:, on_error:)
    return default if str.blank?
    Time.iso8601(str)
  rescue ArgumentError
    on_error.call
    default
  end
end
