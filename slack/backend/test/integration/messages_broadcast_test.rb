require "test_helper"

class MessagesBroadcastTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    suffix = SecureRandom.hex(4)
    @account = Account.create!(email: "alice-#{suffix}@test.com", password_hash: "dummy", status: 2)
    @user = User.create!(id: @account.id, display_name: "Alice")
    @channel = ::Channel.create!(name: "general-#{suffix}", kind: "public")
    Membership.create!(user: @user, channel: @channel, role: "member")
    @token = JWT.encode(
      { "account_id" => @account.id, "authenticated_by" => ["password"] },
      Rails.application.secret_key_base,
      "HS256"
    )
  end

  test "POST /channels/:id/messages broadcasts to the channel stream" do
    assert_broadcasts(MessagesChannel.broadcasting_for(@channel), 1) do
      post "/channels/#{@channel.id}/messages",
        params: { body: "hello over websocket" }.to_json,
        headers: { "Content-Type" => "application/json", "Authorization" => @token }
    end

    assert_response :created
    assert_schema_conform(201)
    body = JSON.parse(@response.body)
    assert_equal "hello over websocket", body["body"]
    assert_equal @user.id, body["user"]["id"]
  end

  test "POST /channels/:id/read broadcasts when cursor advances" do
    msg = @channel.messages.create!(user: @user, body: "first")

    assert_broadcasts(UserChannel.broadcasting_for(@user), 1) do
      post "/channels/#{@channel.id}/read",
        params: { message_id: msg.id }.to_json,
        headers: { "Content-Type" => "application/json", "Authorization" => @token }
    end

    assert_response :success
    assert_schema_conform(200)
  end

  test "POST /channels/:id/read does not broadcast when cursor cannot advance" do
    msg = @channel.messages.create!(user: @user, body: "first")
    Membership.find_by(user: @user, channel: @channel).update!(last_read_message_id: msg.id, last_read_at: Time.current)

    assert_no_broadcasts(UserChannel.broadcasting_for(@user)) do
      post "/channels/#{@channel.id}/read",
        params: { message_id: msg.id }.to_json,
        headers: { "Content-Type" => "application/json", "Authorization" => @token }
    end
  end
end
