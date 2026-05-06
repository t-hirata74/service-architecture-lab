# ADR 0002: Pundit policy は MeetingPermissionResolver を呼ぶだけの薄い層に留める (github と同形 2 層)。
# Resolver にロジックを集約することで、controller 以外 (job / GraphQL field) からも同じ判定を再利用できる。
class MeetingPolicy < ApplicationPolicy
  # 認証済みユーザは会議詳細 (タイトル / 状態 / 参加者一覧) を見られる。
  # Zoom は招待リンクを共有する前提なので、リンクを持つ user は join できる程度の情報は見える。
  # 録画・要約は別 endpoint (view_summary?) で再判定。
  def show?
    !user.nil?
  end

  def create?
    !user.nil?
  end

  def open_waiting_room? = resolver.can_open_waiting_room?
  def go_live?           = resolver.can_go_live?
  def end_meeting?       = resolver.can_end?
  def admit?             = resolver.can_admit_from_waiting_room?
  def force_mute?        = resolver.can_force_mute?
  def force_remove?      = resolver.can_force_remove_participant?
  def transfer_host?     = resolver.can_transfer_host?
  def grant_co_host?     = resolver.can_grant_co_host?
  def revoke_co_host?    = resolver.can_revoke_co_host?
  def retry_recording?   = resolver.can_retry_recording?
  def retry_summary?     = resolver.can_retry_summary?
  def view_summary?      = resolver.can_view_summary?

  private

  def resolver
    @resolver ||= MeetingPermissionResolver.new(record, user)
  end
end
