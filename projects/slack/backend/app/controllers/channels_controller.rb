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

  # public チャンネルへの参加 (idempotent)
  def join
    channel = Channel.find(params[:id])
    unless channel.kind == "public"
      return render json: { error: "public 以外のチャンネルへは参加できません" }, status: :forbidden
    end

    membership = Membership.find_or_create_by!(user: current_user, channel: channel) do |m|
      m.role = "member"
    end

    render json: { id: membership.id, channel: serialize(channel) }, status: :ok
  end

  # ADR 0002: 単調増加ガード付きで last_read_message_id を進め、他デバイスへ broadcast
  def read
    channel = current_user.channels.find(params[:id])
    membership = current_user.memberships.find_by!(channel: channel)
    message_id = Integer(params.require(:message_id))
    advanced = membership.advance_read_cursor!(message_id)
    last_read = membership.reload.last_read_message_id

    if advanced
      UserChannel.broadcast_to(current_user, type: "read.advanced", channel_id: channel.id, last_read_message_id: last_read)
    end

    render json: { last_read_message_id: last_read, advanced: advanced }
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
