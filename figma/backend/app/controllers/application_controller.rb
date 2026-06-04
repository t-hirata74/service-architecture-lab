class ApplicationController < ActionController::API
  include Pundit::Authorization

  class Unauthorized < StandardError; end
  class Forbidden < StandardError; end

  rescue_from Unauthorized do |_e|
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  rescue_from Forbidden do |_e|
    render json: { error: "forbidden" }, status: :forbidden
  end

  rescue_from Pundit::NotAuthorizedError do |_e|
    render json: { error: "forbidden" }, status: :forbidden
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: "invalid", message: e.record.errors.full_messages.join(", ") },
           status: :unprocessable_entity
  end

  # OperationApplier の入力検証エラーは 422 (ADR 0001/0002)。
  rescue_from OperationApplier::InvalidOperation do |e|
    render json: { error: "invalid_operation", message: e.message }, status: :unprocessable_entity
  end

  # rodauth JWT bearer から現在の User を解決する (ADR 0004 / calendly と同形)。
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

    User.find_by(id: account_id) || raise(Unauthorized, "user not provisioned")
  end
end
