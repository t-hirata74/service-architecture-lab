class UploadsController < ApplicationController
  # POST /uploads
  # 認証は Phase 4 以降で導入。Phase 3 では user_email を直接受け取る。
  # multipart/form-data: file, title, description, user_email
  def create
    user = User.find_by!(email: params.require(:user_email))
    file = params.require(:file)

    video = nil
    Video.transaction do
      video = user.videos.create!(
        title: params.require(:title),
        description: params[:description],
        status: :uploaded
      )
      video.original.attach(file)
      video.start_transcoding!
    end

    render json: serialize(video), status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: "user_not_found" }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def serialize(video)
    {
      id: video.id,
      title: video.title,
      status: video.status,
      author: { id: video.user_id, name: video.user.name },
      original_filename: video.original.filename.to_s
    }
  end
end
