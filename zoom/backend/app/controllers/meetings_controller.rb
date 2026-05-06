# Phase 4-1: 会議ライフサイクルの REST 入口。
# 状態遷移ロジックは Meeting モデル (ADR 0001) に集約済み、controller は権限判定 (Pundit + Resolver / ADR 0002)
# とパラメタ整形だけを担う薄い層に保つ。
class MeetingsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_meeting, except: [:create]

  # POST /meetings { title, scheduled_start_at }
  def create
    meeting = Meeting.create!(
      host: current_user,
      title: params.fetch(:title),
      scheduled_start_at: params.fetch(:scheduled_start_at)
    )
    render json: meeting_json(meeting), status: :created
  end

  # GET /meetings/:id
  def show
    authorize @meeting, :show?
    render json: meeting_json(@meeting, include_participants: true)
  end

  # POST /meetings/:id/open  (scheduled → waiting_room)
  def open
    authorize @meeting, :open_waiting_room?
    @meeting.open_waiting_room!
    render json: meeting_json(@meeting.reload)
  end

  # POST /meetings/:id/start  (waiting_room → live)
  def start
    authorize @meeting, :go_live?
    @meeting.go_live!
    render json: meeting_json(@meeting.reload)
  end

  # POST /meetings/:id/join  (現 user を waiting participant として登録)
  def join
    participant = Participant.find_or_create_by!(meeting: @meeting, user: current_user) do |p|
      p.status = "waiting"
    end
    render json: { id: participant.id, status: participant.status }, status: :accepted
  end

  # POST /meetings/:id/admit { user_id }
  def admit
    authorize @meeting, :admit?
    target = @meeting.participants.find_by!(user_id: params.fetch(:user_id))
    target.admit!

    # 最初の admit と同時に live に進める (UI フローを単純化)。既に live なら no-op。
    @meeting.go_live! if @meeting.waiting_room?
    render json: meeting_json(@meeting.reload, include_participants: true)
  end

  # POST /meetings/:id/leave  (現 user の退出)
  def leave
    p = @meeting.participants.find_by!(user_id: current_user.id)
    p.leave!
    render json: { id: p.id, status: p.status }
  end

  # POST /meetings/:id/end  (live → ended、FinalizeRecordingJob を enqueue)
  def end
    authorize @meeting, :end_meeting?
    @meeting.end_meeting!
    FinalizeRecordingJob.perform_later(@meeting.id)
    render json: meeting_json(@meeting.reload)
  end

  # POST /meetings/:id/transfer_host { to_user_id, reason? }
  def transfer_host
    authorize @meeting, :transfer_host?
    new_host = User.find(params.fetch(:to_user_id))
    @meeting.transfer_host_to!(new_host, reason: params[:reason] || "voluntary")
    render json: meeting_json(@meeting.reload)
  end

  # POST /meetings/:id/retry_summary  (summarize_failed からの再要約)
  def retry_summary
    authorize @meeting, :retry_summary?
    SummarizeMeetingJob.perform_later(@meeting.id)
    render json: { status: "enqueued" }, status: :accepted
  end

  # GET /meetings/:id/summary
  def summary
    authorize @meeting, :view_summary?
    s = @meeting.summary
    return render(json: { error: "summary_not_ready", status: @meeting.status }, status: :not_found) if s.nil?

    render json: { meeting_id: @meeting.id, body: s.body, generated_at: s.generated_at }
  end

  private

  def load_meeting
    @meeting = Meeting.find(params[:id])
  end

  def meeting_json(m, include_participants: false)
    base = {
      id: m.id,
      title: m.title,
      status: m.status,
      host_id: m.host_id,
      scheduled_start_at: m.scheduled_start_at,
      started_at: m.started_at,
      ended_at: m.ended_at
    }
    return base unless include_participants

    base.merge(
      participants: m.participants.includes(:user).map do |p|
        { id: p.id, user_id: p.user_id, display_name: p.user.display_name, status: p.status }
      end,
      co_hosts: m.meeting_co_hosts.pluck(:user_id)
    )
  end
end
