class UserChannel < ApplicationCable::Channel
  # ADR 0002: 既読 cursor の多デバイス同期用、ユーザー専用ストリーム
  def subscribed
    stream_for current_user
  end
end
