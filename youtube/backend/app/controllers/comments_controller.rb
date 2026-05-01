class CommentsController < ApplicationController
  before_action :load_video

  # GET /videos/:video_id/comments
  # 公開可能 (viewable) な動画のみコメントを返す。
  def index
    comments = @video.comments.includes(:user, replies: :user).top_level
    render json: { items: comments.map { |c| serialize(c) } }
  end

  # POST /videos/:video_id/comments
  # Phase 5: 認証なし。user_email + body (+ parent_id) で投稿。
  def create
    user = User.find_by!(email: params.require(:user_email))
    comment = @video.comments.build(
      user: user,
      body: params[:body].to_s,
      parent_id: params[:parent_id]
    )
    if comment.save
      render json: serialize(comment.reload), status: :created
    else
      render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "user_not_found" }, status: :not_found
  end

  private

  def load_video
    @video = Video.viewable.find_by(id: params[:video_id])
    render(json: { error: "not_found" }, status: :not_found) unless @video
  end

  def serialize(comment)
    {
      id: comment.id,
      body: comment.body,
      created_at: comment.created_at.iso8601,
      author: { id: comment.user_id, name: comment.user.name },
      parent_id: comment.parent_id,
      replies: comment.replies.map { |r| serialize_reply(r) }
    }
  end

  def serialize_reply(reply)
    {
      id: reply.id,
      body: reply.body,
      created_at: reply.created_at.iso8601,
      author: { id: reply.user_id, name: reply.user.name },
      parent_id: reply.parent_id
    }
  end
end
