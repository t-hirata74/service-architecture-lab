class VideosController < ApplicationController
  # GET /videos
  # 公開済みの一覧を新しい順で返す。ページネーションは Phase 5 で。
  def index
    videos = Video.listable.includes(:user, :tags).limit(50)
    render json: { items: videos.map { |v| serialize(v, summary: true) } }
  end

  # GET /videos/:id
  # ready / published のみ閲覧可。それ以外は 404 で隠す。
  def show
    video = Video.viewable.includes(:user, :tags).find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found unless video
    render json: serialize(video, summary: false)
  end

  # GET /videos/:id/status
  # ステータスのみを返すポーリング用エンドポイント (Phase 3)。
  # アップロード後のフロントエンドが transcoding → ready 遷移を観測するために使う。
  def status
    video = Video.find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found unless video
    render json: { id: video.id, status: video.status }
  end

  # GET /videos/:id/recommendations
  # ADR 0003: 関連動画を ai-worker で計算する。Rails は対象 + 候補集合を渡し、
  # ai-worker のスコアリング結果に対応する Video レコードを返す。
  def recommendations
    target = Video.viewable.find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found unless target

    candidates = Video.listable.where.not(id: target.id).limit(50).to_a
    items = AiWorkerClient.recommend(target: target, candidates: candidates, limit: 5)
    by_id = candidates.index_by(&:id)
    payload = items.map do |item|
      video = by_id[item["id"]]
      next unless video
      serialize(video, summary: true).merge(score: item["score"])
    end.compact

    render json: { items: payload }
  rescue AiWorkerClient::Error => e
    Rails.logger.warn("recommendations failed: #{e.class}: #{e.message}")
    render json: { items: [], degraded: true }, status: :ok
  end

  # POST /videos/:id/publish
  # ready -> published への遷移。Phase 3 では認証なしで誰でも公開できる。
  def publish
    video = Video.find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found unless video
    video.publish!
    render json: serialize(video.reload, summary: false)
  rescue Video::InvalidTransition => e
    render json: { error: "invalid_transition", detail: e.message }, status: :conflict
  end

  # POST /videos
  # 管理用シンプル作成（ファイルなし）。Active Storage 添付つきは POST /uploads を使う。
  def create
    user = User.find_by!(email: params.require(:user_email))
    video = user.videos.build(video_params)
    if video.save
      assign_tags!(video, params[:tags])
      render json: serialize(video, summary: false), status: :created
    else
      render json: { errors: video.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def video_params
    params.permit(:title, :description, :duration_seconds, :status)
  end

  def assign_tags!(video, names)
    return if names.blank?
    tags = Tag.upsert_all_by_name(Array(names))
    video.tags = tags
  end

  def serialize(video, summary:)
    base = {
      id: video.id,
      title: video.title,
      status: video.status,
      duration_seconds: video.duration_seconds,
      published_at: video.published_at&.iso8601,
      author: { id: video.user_id, name: video.user.name },
      tags: video.tags.map(&:name),
      thumbnail_url: thumbnail_url_for(video)
    }
    return base if summary
    base.merge(description: video.description)
  end

  def thumbnail_url_for(video)
    return nil unless video.thumbnail.attached?
    Rails.application.routes.url_helpers.rails_blob_url(
      video.thumbnail,
      host: ENV.fetch("BACKEND_PUBLIC_URL", "http://localhost:3020")
    )
  end
end
