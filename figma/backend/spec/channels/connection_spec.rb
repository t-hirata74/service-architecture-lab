require "rails_helper"

# ADR 0004: ActionCable Connection の JWT 認証 (?token=<jwt>)。
RSpec.describe ApplicationCable::Connection, type: :channel do
  it "token 無しは reject" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "不正な token は reject" do
    expect { connect "/cable?token=garbage" }.to have_rejected_connection
  end

  it "有効な JWT (account_id) で current_user を確立する" do
    user = create(:user)
    secret = ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base)
    token = JWT.encode({ "account_id" => user.id }, secret, "HS256")

    connect "/cable?token=#{token}"
    expect(connection.current_user).to eq(user)
  end
end
