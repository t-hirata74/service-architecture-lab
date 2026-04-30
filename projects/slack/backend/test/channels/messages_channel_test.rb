require "test_helper"

class MessagesChannelTest < ActionCable::Channel::TestCase
  setup do
    suffix = SecureRandom.hex(4)
    @account = Account.create!(email: "alice-#{suffix}@test.com", password_hash: "dummy", status: 2)
    @user = User.create!(id: @account.id, display_name: "Alice")
    @channel = ::Channel.create!(name: "general-#{suffix}", kind: "public")
    stub_connection current_user: @user
  end

  test "rejects when channel does not exist" do
    subscribe channel_id: 999_999_999
    assert subscription.rejected?
  end

  test "rejects when user is not a member" do
    subscribe channel_id: @channel.id
    assert subscription.rejected?
  end

  test "subscribes member and streams for the channel" do
    Membership.create!(user: @user, channel: @channel, role: "member")
    subscribe channel_id: @channel.id

    assert subscription.confirmed?
    assert_has_stream_for @channel
  end
end
