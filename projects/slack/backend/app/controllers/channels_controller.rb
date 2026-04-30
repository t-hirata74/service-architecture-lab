class ChannelsController < ApplicationController
  def index
    channels = current_user.channels.order(:id)
    render json: { channels: channels.map { |c| serialize(c) } }
  end

  def create
    channel = nil
    Channel.transaction do
      channel = Channel.create!(channel_params)
      Membership.create!(user: current_user, channel: channel, role: "admin")
    end
    render json: serialize(channel), status: :created
  end

  # ADR 0002: 単調増加ガード付きで last_read_message_id を進める
  def read
    channel = current_user.channels.find(params[:id])
    membership = current_user.memberships.find_by!(channel: channel)
    message_id = Integer(params.require(:message_id))
    advanced = membership.advance_read_cursor!(message_id)
    render json: {
      last_read_message_id: membership.reload.last_read_message_id,
      advanced: advanced
    }
  end

  private

  def channel_params
    params.permit(:name, :kind, :topic).tap do |p|
      p[:kind] ||= "public"
    end
  end

  def serialize(c)
    { id: c.id, name: c.name, kind: c.kind, topic: c.topic }
  end
end
