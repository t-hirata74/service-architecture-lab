require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  setup do
    suffix = SecureRandom.hex(4)
    @account = Account.create!(email: "alice-#{suffix}@test.com", password_hash: "dummy", status: 2)
    @user = User.create!(id: @account.id, display_name: "Alice")
  end

  test "rejects connection without token" do
    assert_reject_connection { connect }
  end

  test "rejects connection with invalid token" do
    assert_reject_connection { connect "/cable?token=invalid.token.value" }
  end

  test "accepts valid JWT and identifies user" do
    token = JWT.encode({ "account_id" => @account.id }, Rails.application.secret_key_base, "HS256")
    connect "/cable?token=#{token}"
    assert_equal @user.id, connection.current_user.id
  end
end
