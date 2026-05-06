# ADR 0003: recorded → summarized を駆動するジョブ。
# at-least-once 前提。summaries.meeting_id UNIQUE が冪等保証の核 (ADR 0003)。
class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  # ADR 0003: 同上。リトライ枯渇は failed_executions に残す → ホスト UI で再要約操作。
  # ※ retry_on は :test adapter では perform_now 後の再実行ではなく enqueue になる。
  retry_on Internal::Client::Timeout, attempts: 5, wait: :polynomially_longer
  retry_on Internal::Client::Error, attempts: 3, wait: 5.seconds

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    return unless %w[recorded summarize_failed].include?(meeting.status)

    recording = meeting.recording
    raise "recording not found for meeting=#{meeting_id}" if recording.nil?

    transcript_seed = build_transcript_seed(meeting, recording)

    result = Internal::Client.summarize(
      meeting_id: meeting.id,
      recording_id: recording.id,
      transcript_seed: transcript_seed
    )

    Summary.upsert(
      {
        meeting_id: meeting.id,
        body: result.fetch("body"),
        input_hash: result.fetch("input_hash"),
        generated_at: Time.current,
        created_at: Time.current,
        updated_at: Time.current
      }
    )

    meeting.mark_summarized!
  rescue Meeting::InvalidTransition
    nil
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  # ai-worker の deterministic mock の入力。会議 ID と duration を含めることで
  # 「同じ会議 → 同じ要約」が安定する (mock の決定性を素直に使うため)。
  def build_transcript_seed(meeting, recording)
    "meeting=#{meeting.id};duration=#{recording.duration_seconds};title=#{meeting.title}"
  end
end
