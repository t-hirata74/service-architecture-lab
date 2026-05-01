module Mutations
  # ADR 0002 MIN_REQUIRED[:submit_review] == :write
  # レビュー提出時に requested_reviewer から自分を外す
  class SubmitReview < BaseMutation
    argument :pull_request_id, ID, required: true
    argument :state, Types::ReviewStateEnum, required: true
    argument :body, String, required: false, default_value: ""

    field :review, Types::ReviewType, null: true
    field :errors, [String], null: false

    def resolve(pull_request_id:, state:, body:)
      user = current_user!
      pr = PullRequest.find_by(id: pull_request_id)
      return { review: nil, errors: ["Pull request not found"] } unless pr

      return { review: nil, errors: ["Forbidden"] } unless authorize!(pr.repository, :submit_review?, strict: false)

      review = nil
      PullRequest.transaction do
        review = pr.reviews.create!(reviewer: user, state: state, body: body)
        pr.requested_reviewers.where(user_id: user.id).destroy_all
      end

      { review: review, errors: [] }
    end
  end
end
