# Phase 1-3: X-User-Id ヘッダで current_user を引く暫定実装。
# Phase 4 で rodauth-rails の cookie auth に差し替える (architecture.md / README 参照).
class ApplicationController < ActionController::API
  class Unauthorized < StandardError; end

  rescue_from Unauthorized do |_e|
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def current_user
    @current_user ||= find_current_user!
  end

  def authenticate_user!
    current_user
  end

  private

  def find_current_user!
    user_id = request.headers["X-User-Id"]
    raise Unauthorized, "X-User-Id header missing" if user_id.blank?

    user = User.find_by(id: user_id)
    raise Unauthorized, "user not found" if user.nil?

    user
  end
end
