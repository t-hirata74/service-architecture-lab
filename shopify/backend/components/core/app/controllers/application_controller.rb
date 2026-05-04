# ADR 0002: 全 controller は middleware が解決した `current_shop` を入口で読み、
# tenant が引けない場合は 404 を返す。
class ApplicationController < ActionController::API
  class Unauthorized < StandardError; end
  class TenantNotFound < StandardError; end

  rescue_from Unauthorized do |_e|
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  rescue_from TenantNotFound do |_e|
    render json: { error: "tenant_not_found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  def current_shop
    request.env["shopify.current_shop"] || raise(TenantNotFound)
  end

  def current_user
    @current_user ||= find_current_user!
  end

  def authenticate_user!
    current_user
  end

  private

  def find_current_user!
    account_id = rodauth.session_value
    raise Unauthorized, "invalid or expired JWT" if account_id.nil?

    user = Core::User.find_by(id: account_id, shop_id: current_shop.id)
    raise Unauthorized, "user not provisioned for tenant" if user.nil?

    user
  end
end
