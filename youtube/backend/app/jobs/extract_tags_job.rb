class ExtractTagsJob < ApplicationJob
  queue_as :ai

  # ai-worker の /tags/extract を呼び、Tag を upsert + Video に紐づける。
  # 既にタグが手動で付いている場合は **追記マージ** する (ユーザーの意思を上書きしない)。
  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    names = AiWorkerClient.extract_tags(title: video.title, description: video.description)
    return if names.empty?

    Video.transaction do
      tags = Tag.upsert_all_by_name(names)
      existing = video.tags.pluck(:id)
      missing = tags.reject { |t| existing.include?(t.id) }
      video.tags << missing if missing.any?
    end
  rescue AiWorkerClient::Error => e
    Rails.logger.warn("ExtractTagsJob video##{video_id} skipped: #{e.message}")
  end
end
