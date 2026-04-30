class MessagesChannel < ApplicationCable::Channel
  # チャンネル単位の購読。メンバーシップを持たないユーザーは reject。
  def subscribed
    channel = Channel.find_by(id: params[:channel_id])
    return reject if channel.nil?
    return reject unless current_user.channels.exists?(id: channel.id)

    stream_for channel
  end
end
