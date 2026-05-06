# ADR 0002: ホスト / 共同ホスト / 参加者の権限判定を 1 箇所に集約する PORO。
# github の `PermissionResolver` と同じ命名規約。Pundit policy はこの Resolver を呼ぶだけの薄い層。
#
# 役割の規律:
#   - host: meetings.host_id 所有者
#   - co_host: meeting_co_hosts に存在する user
#   - participant: participants.status == 'live' な user
#   - guest: それ以外 (waiting / left / 無関係)
#
# 動的譲渡 (ADR 0002) があるため、判定は **その瞬間の DB の状態** で行う。
# キャッシュは入れない (live 中の譲渡が即座に反映される必要がある)。
class MeetingPermissionResolver
  def initialize(meeting, user)
    @meeting = meeting
    @user = user
  end

  # ----- 役割の判定 -----

  def host?
    return false if @user.nil?
    @meeting.host_id == @user.id
  end

  def co_host?
    return false if @user.nil?
    @meeting.meeting_co_hosts.exists?(user_id: @user.id)
  end

  def live_participant?
    return false if @user.nil?
    @meeting.participants.where(user_id: @user.id, status: "live").exists?
  end

  def host_or_co_host?
    host? || co_host?
  end

  # ----- 操作の権限 (ADR 0001 の状態遷移メソッドを誰が叩けるか) -----

  def can_open_waiting_room?
    host?
  end

  def can_go_live?
    host?
  end

  def can_end?
    host?
  end

  # 待機室からの入室許可。共同ホストにも委譲する。
  def can_admit_from_waiting_room?
    host_or_co_host?
  end

  # 強制ミュート / 強制退出。共同ホストにも委譲する。
  def can_force_mute?
    host_or_co_host?
  end

  def can_force_remove_participant?
    host_or_co_host?
  end

  # ----- 動的譲渡まわり (ADR 0002 の主役) -----

  def can_transfer_host?
    host?
  end

  def can_grant_co_host?
    host?
  end

  def can_revoke_co_host?
    host?
  end

  # ----- 録画 / 要約パイプライン (ADR 0003) の発火権限 -----

  def can_retry_recording?
    host?
  end

  def can_retry_summary?
    host?
  end

  # ----- 表示・閲覧 -----

  def can_view_summary?
    host_or_co_host? || live_participant_or_left?
  end

  private

  def live_participant_or_left?
    return false if @user.nil?
    @meeting.participants.where(user_id: @user.id, status: %w[live left]).exists?
  end
end
