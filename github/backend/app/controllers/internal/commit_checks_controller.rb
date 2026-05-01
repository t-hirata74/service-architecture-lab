module Internal
  # ADR 0004: ai-worker からの check 通知を受ける trusted ingress。
  # GraphQL は外向き、内部からの状態書き込みは REST に倒す方針。
  class CommitChecksController < ApplicationController
    before_action :authenticate_internal!

    def create
      org = Organization.find_by!(login: params.require(:owner))
      repository = org.repositories.find_by!(name: params.require(:name))

      record = CommitCheck.upsert_check!(
        repository: repository,
        head_sha: params.require(:head_sha),
        name: params.require(:check_name),
        state: params.require(:state),
        output: params[:output],
        started_at: parse_time(params[:started_at]),
        completed_at: parse_time(params[:completed_at])
      )

      render json: serialize(record), status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { error: "repository not found" }, status: :not_found
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue ArgumentError => e
      # enum invalid value 等
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    DEV_DEFAULT_TOKEN = "dev-internal-token".freeze

    def authenticate_internal!
      expected = ENV["INTERNAL_INGRESS_TOKEN"].presence || DEV_DEFAULT_TOKEN
      # 本番環境で開発用デフォルトトークンが残っていたら即座に拒否
      if Rails.env.production? && expected == DEV_DEFAULT_TOKEN
        head :service_unavailable
        return
      end
      provided = request.headers["X-Internal-Token"]
      head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected.to_s, provided.to_s)
    end

    def parse_time(value)
      value.present? ? Time.iso8601(value) : nil
    rescue ArgumentError
      nil
    end

    def serialize(record)
      {
        id: record.id,
        repository_id: record.repository_id,
        head_sha: record.head_sha,
        name: record.name,
        state: record.state,
        started_at: record.started_at&.iso8601,
        completed_at: record.completed_at&.iso8601,
        output: record.output
      }
    end
  end
end
