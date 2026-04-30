class TranscodeJob < ApplicationJob
  queue_as :transcode

  # ADR 0001: 動画変換の "ふり" をするモック実装。
  # 本番では FFmpeg 等で実コーデック処理を行う想定。
  # 添付がない場合は `failed` に遷移して学習材料にする。
  def perform(video_id)
    video = Video.find(video_id)
    return unless video.transcoding?

    sleep_for_demo

    if video.original.attached?
      video.mark_ready!
    else
      video.mark_failed!("original attachment missing")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("TranscodeJob: video##{video_id} not found")
  end

  private

  # 本番のコーデック処理は数十秒〜分単位だが、学習用は短く
  def sleep_for_demo
    return if Rails.env.test?
    sleep(ENV.fetch("TRANSCODE_MOCK_SLEEP_SECONDS", "1.5").to_f)
  end
end
