# ADR 0001: 会議ライフサイクルの状態機械。
# 取りうる status は STATUSES 定数で固定、遷移は TRANSITIONS で表現。
# すべての状態遷移は `with_lock` で直列化され、既に target 状態なら冪等に no-op になる。
class Meeting < ApplicationRecord
  STATUSES = %w[
    scheduled
    waiting_room
    live
    ended
    recorded
    summarized
    recording_failed
    summarize_failed
  ].freeze

  # ADR 0001: 戻り遷移 (recording_failed → recorded, summarize_failed → summarized)
  # は再試行で吸収する設計。
  TRANSITIONS = {
    "scheduled"        => %w[waiting_room],
    "waiting_room"     => %w[live],
    "live"             => %w[ended],
    "ended"            => %w[recorded recording_failed],
    "recorded"         => %w[summarized summarize_failed],
    "recording_failed" => %w[recorded],
    "summarize_failed" => %w[summarized],
    "summarized"       => [],
  }.freeze

  class InvalidTransition < StandardError; end

  belongs_to :host, class_name: "User"
  has_many :participants, dependent: :destroy
  has_many :meeting_co_hosts, dependent: :destroy
  has_many :host_transfers, dependent: :restrict_with_error
  has_one :recording, dependent: :destroy
  has_one :summary, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_start_at, presence: true

  STATUSES.each do |s|
    define_method("#{s}?") { status == s }
  end

  # ----- transitions -----

  def open_waiting_room!
    transition_to!("waiting_room")
  end

  def go_live!
    transition_to!("live") { self.started_at ||= Time.current }
  end

  # `end` は予約語ではないが、紛らわしいため end_meeting! を採用。
  def end_meeting!
    transition_to!("ended") { self.ended_at ||= Time.current }
  end

  def mark_recorded!
    transition_to!("recorded")
  end

  def mark_summarized!
    transition_to!("summarized")
  end

  def mark_recording_failed!
    transition_to!("recording_failed")
  end

  def mark_summarize_failed!
    transition_to!("summarize_failed")
  end

  # ADR 0002: 動的譲渡。host_id 更新と host_transfers insert を with_lock で atomic に。
  def transfer_host_to!(new_host, reason: "voluntary", at: Time.current)
    raise ArgumentError, "new_host must be a User" unless new_host.is_a?(User)

    with_lock do
      raise InvalidTransition, "cannot transfer when status=#{status}" unless live?
      raise ArgumentError, "new_host must differ from current host" if host_id == new_host.id
      unless participants.where(user_id: new_host.id, status: "live").exists?
        raise InvalidTransition, "new_host is not a live participant"
      end

      prev_host_id = host_id
      update!(host_id: new_host.id)
      host_transfers.create!(
        from_user_id: prev_host_id,
        to_user_id: new_host.id,
        transferred_at: at,
        reason: reason
      )
    end
  end

  private

  # 状態遷移の中核。
  # - `with_lock` で直列化
  # - 既に target 状態なら no-op (at-least-once の冪等性、並行 end! 対応)
  # - 不正遷移は InvalidTransition
  def transition_to!(new_status)
    with_lock do
      reload
      return if status == new_status

      allowed_sources = TRANSITIONS.select { |_, dests| dests.include?(new_status) }.keys
      unless allowed_sources.include?(status)
        raise InvalidTransition, "cannot transition #{status} -> #{new_status}"
      end

      yield if block_given?
      self.status = new_status
      save!
    end
  end
end
