# ADR 0003: ended → recorded を駆動するジョブ。
# at-least-once 前提。recordings.meeting_id UNIQUE で 2 回目以降の重複挿入を弾く。
class FinalizeRecordingJob < ApplicationJob
  queue_as :default

  # ADR 0003: at-least-once 前提のリトライ。枯渇時は Solid Queue の failed_executions に残る。
  # 失敗状態 (recording_failed) への自動遷移はリトライループとの相互作用が複雑になるため、
  # MVP では「リトライ枯渇 → failed_executions に残す → ホスト UI から手動再開 (perform_later)」
  # で割り切る。手動 mark_recording_failed! は別操作 (controller) で扱う。
  retry_on StandardError, attempts: 5, wait: :polynomially_longer

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)

    # 既に recorded / summarized などへ進んでいたら no-op (冪等)。
    return unless %w[ended recording_failed].include?(meeting.status)

    # mock blob "保存"。実 blob は無し (policy: WebRTC は別領域)。
    blob_path = "mock://recordings/meeting-#{meeting_id}.bin"
    duration = compute_mock_duration(meeting)

    Recording.upsert(
      {
        meeting_id: meeting.id,
        mock_blob_path: blob_path,
        duration_seconds: duration,
        finalized_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    )

    meeting.mark_recorded!
    SummarizeMeetingJob.perform_later(meeting.id)
  rescue Meeting::InvalidTransition
    # mark_recorded! の遷移失敗は他の job が先行した可能性あり。冪等に終了。
    nil
  rescue ActiveRecord::RecordNotUnique
    # 並行で 2 つ走った場合の保険。冪等に終了。
    nil
  rescue StandardError => e
    # retry_on の上限超過時、ここに到達することはない (例外が再 raise される)。
    # 上限超過した場合は SolidQueue の failed_executions に残る。
    # ただし「明示的に recording_failed に落とす」必要がある場合は外側でハンドル。
    Rails.logger.error("FinalizeRecordingJob failed: #{e.message}")
    raise
  end

  private

  def compute_mock_duration(meeting)
    return 0 if meeting.started_at.nil? || meeting.ended_at.nil?
    (meeting.ended_at - meeting.started_at).to_i
  end
end
