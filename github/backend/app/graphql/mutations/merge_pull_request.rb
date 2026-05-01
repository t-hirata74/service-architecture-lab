module Mutations
  # ADR 0002 MIN_REQUIRED[:merge] == :maintain
  class MergePullRequest < BaseMutation
    argument :pull_request_id, ID, required: true

    field :pull_request, Types::PullRequestType, null: true
    field :errors, [String], null: false

    def resolve(pull_request_id:)
      current_user!
      pr = PullRequest.find_by(id: pull_request_id)
      return { pull_request: nil, errors: ["Pull request not found"] } unless pr

      return { pull_request: nil, errors: ["Forbidden"] } unless authorize!(pr.repository, :merge_pull_request?, strict: false)

      begin
        pr.merge!
      rescue PullRequest::InvalidTransition => e
        return { pull_request: nil, errors: [e.message] }
      end

      { pull_request: pr, errors: [] }
    end
  end
end
