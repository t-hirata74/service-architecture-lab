class MessagesController < ApplicationController
  before_action :set_channel

  # ADR 0002: (channel_id, id) インデックスで降順タイムラインを取得、
  # before パラメータで cursor ページング
  def index
    scope = @channel.messages.active.includes(:user).order(id: :desc)
    scope = scope.where("messages.id < ?", params[:before]) if params[:before].present?
    limit = [params.fetch(:limit, 50).to_i, 100].min
    rows = scope.limit(limit + 1).to_a
    has_more = rows.size > limit
    messages = rows.first(limit)

    render json: {
      messages: messages.map { |m| serialize(m) },
      next_cursor: has_more ? messages.last.id : nil
    }
  end

  def create
    message = @channel.messages.create!(message_params.merge(user: current_user))
    render json: serialize(message), status: :created
  end

  private

  def set_channel
    @channel = current_user.channels.find(params[:channel_id])
  end

  def message_params
    params.permit(:body, :parent_message_id)
  end

  def serialize(m)
    {
      id: m.id,
      body: m.body,
      parent_message_id: m.parent_message_id,
      edited_at: m.edited_at,
      created_at: m.created_at,
      user: { id: m.user_id, display_name: m.user&.display_name }
    }
  end
end
