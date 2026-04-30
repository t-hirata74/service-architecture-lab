class ChannelsController < ApplicationController
  def index
    channels = current_user.channels.order(:id).to_a
    memberships_by_channel = current_user.memberships.index_by(&:channel_id)

    data = channels.map do |c|
      membership = memberships_by_channel[c.id]
      serialize(c).merge(
        last_read_message_id: membership&.last_read_message_id,
        latest_message_id: c.messages.active.maximum(:id),
      )
    end
    render json: { channels: data }
  end

  def create
    channel = nil
    Channel.transaction do
      channel = Channel.create!(channel_params)
      Membership.create!(user: current_user, channel: channel, role: "admin")
    end
    render json: serialize(channel), status: :created
  end

  # ai-worker によるチャンネル要約 (モック)
  def summary
    channel = current_user.channels.find(params[:id])
    recent = channel.messages.active.includes(:user).order(id: :desc).limit(30).reverse
    result = AiWorkerClient.new.summarize(channel_name: channel.name, messages: recent)
    render json: result
  rescue AiWorkerClient::Error => e
    render json: { error: e.message }, status: :bad_gateway
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
