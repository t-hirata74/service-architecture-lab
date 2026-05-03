# ADR 0007: 認証経路.
#
# Phase 5 で rodauth-rails (JWT bearer) を導入した. ただし既存 (Phase 1-4) の RSpec /
# 開発フローは X-User-Id ヘッダ前提なので、トランジショナル期間として両方を受け付ける:
#
#   - Authorization: Bearer <jwt> が **あれば** rodauth で検証して current_user を引く
#   - 無い場合は X-User-Id ヘッダ (dev/test 専用. production では 401) でフォールバック
#
# 完全移行後 (frontend が常に JWT を送るようになったら) X-User-Id 経路は削除する.
class ApplicationController < ActionController::API
  class Unauthorized < StandardError; end

  rescue_from Unauthorized do |_e|
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  def current_user
    @current_user ||= find_current_user!
  end

  def authenticate_user!
    current_user
  end

  private

  def find_current_user!
    if jwt_present?
      account_id = rodauth_account_id_or_unauthorized!
      User.find_by(id: account_id) || raise(Unauthorized, "user not provisioned for account")
    else
      authenticate_via_dev_header!
    end
  end

  def jwt_present?
    request.headers["Authorization"].present?
  end

  # rodauth.session_value は JWT が valid な時に account_id を返し、無効/欠損なら nil.
  # halt 動作の require_account ではなく非破壊的に確認する.
  def rodauth_account_id_or_unauthorized!
    id = rodauth.session_value
    raise Unauthorized, "invalid or expired JWT" if id.nil?

    id
  end

  def authenticate_via_dev_header!
    raise Unauthorized, "X-User-Id is disabled in production" if Rails.env.production?

    user_id = request.headers["X-User-Id"]
    raise Unauthorized, "X-User-Id header missing" if user_id.blank?

    parsed_id = Integer(user_id, 10) rescue nil
    raise Unauthorized, "X-User-Id must be integer" if parsed_id.nil?

    user = User.find_by(id: parsed_id)
    raise Unauthorized, "user not found" if user.nil?

    user
  end
end
