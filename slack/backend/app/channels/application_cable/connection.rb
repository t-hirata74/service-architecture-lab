module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # ADR 0001 / 0004: WebSocket は URL クエリ token=<JWT> で認証する
    # (ブラウザ WebSocket API はカスタムヘッダ送信不可のため)
    def find_verified_user
      token = request.params[:token]
      reject_unauthorized_connection if token.blank?

      payload, _header = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256")
      User.find(payload.fetch("account_id"))
    rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound
      reject_unauthorized_connection
    end
  end
end
