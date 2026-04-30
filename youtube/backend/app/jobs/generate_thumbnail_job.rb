class GenerateThumbnailJob < ApplicationJob
  queue_as :ai

  # ai-worker の /thumbnail (PNG) を取得して Active Storage に保存する。
  # 失敗時は nil を返すクライアント仕様。サムネが無くても本流は動く。
  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    png = AiWorkerClient.generate_thumbnail(video_id: video.id, title: video.title)
    return unless png

    video.thumbnail.attach(
      io: StringIO.new(png),
      filename: "video-#{video.id}.png",
      content_type: "image/png"
    )
  end
end
