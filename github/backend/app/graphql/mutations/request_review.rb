module Mutations
  # ADR 0002 MIN_REQUIRED[:request_review] == :write
  class RequestReview < BaseMutation
    argument :pull_request_id, ID, required: true
    argument :reviewer_logins, [String], required: true

    field :pull_request, Types::PullRequestType, null: true
    field :errors, [String], null: false

    def resolve(pull_request_id:, reviewer_logins:)
      current_user!
      pr = PullRequest.find_by(id: pull_request_id)
      return { pull_request: nil, errors: ["Pull request not found"] } unless pr

      resolver = PermissionResolver.new(context[:current_user], pr.repository)
      return { pull_request: nil, errors: ["Forbidden"] } unless resolver.can?(:request_review)

      users = User.where(login: reviewer_logins).to_a
      missing = reviewer_logins - users.map(&:login)
      return { pull_request: nil, errors: ["Unknown logins: #{missing.join(', ')}"] } if missing.any?

      PullRequest.transaction do
        users.each do |u|
          pr.requested_reviewers.find_or_create_by!(user: u)
        end
      end

      { pull_request: pr.reload, errors: [] }
    end
  end
end
