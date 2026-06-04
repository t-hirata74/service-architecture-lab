module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # ADR 0004: WebSocket は URL クエリ token=<JWT> で認証する
    # (ブラウザ WebSocket API はカスタムヘッダを送れないため)。REST と同じ rodauth JWT を共有する。
    def find_verified_user
      token = request.params[:token]
      reject_unauthorized_connection if token.blank?

      secret = ENV.fetch("RODAUTH_JWT_SECRET", Rails.application.secret_key_base)
      payload, _header = JWT.decode(token, secret, true, algorithm: "HS256")
      User.find(payload.fetch("account_id"))
    rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
      reject_unauthorized_connection
    end
  end
end
