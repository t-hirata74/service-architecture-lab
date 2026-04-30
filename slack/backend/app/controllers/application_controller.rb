class ApplicationController < ActionController::API
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  # rodauth (ADR 0004): JWT が無効/欠損なら 401 JSON を返す
  def authenticate!
    rodauth.require_account
  end

  def current_user
    @current_user ||= User.find(rodauth.account_id)
  end
end
