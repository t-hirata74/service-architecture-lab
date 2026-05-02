# Phase 1-3: X-User-Id ヘッダで current_user を引く暫定実装。
# Phase 4 で rodauth-rails の cookie auth に差し替える (architecture.md / README 参照).
#
# operating-patterns.md §7 整合:
#   X-User-Id は trivially spoofable な開発専用認証。production 環境で誤って
#   有効化することを防ぐため、Rails.env.production? では一律 401 で reject する.
#   Phase 4 で rodauth-rails が入れば本ファイルからこの暫定経路は削除する.
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
    # production 誤デプロイ防御: Phase 4 まで X-User-Id は dev/test 専用
    raise Unauthorized, "X-User-Id is disabled in production" if Rails.env.production?

    user_id = request.headers["X-User-Id"]
    raise Unauthorized, "X-User-Id header missing" if user_id.blank?

    # 整数以外 (e.g. "abc") は Integer() で握り潰して 401
    parsed_id = Integer(user_id, 10) rescue nil
    raise Unauthorized, "X-User-Id must be integer" if parsed_id.nil?

    user = User.find_by(id: parsed_id)
    raise Unauthorized, "user not found" if user.nil?

    user
  end
end
