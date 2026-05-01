module Mutations
  # ADR 0003: PR 番号は IssueNumberAllocator を経由して issue と同じ空間を共有。
  class CreatePullRequest < BaseMutation
    argument :owner, String, required: true
    argument :name, String, required: true
    argument :title, String, required: true
    argument :body, String, required: false, default_value: ""
    argument :head_ref, String, required: true
    argument :base_ref, String, required: false, default_value: "main"
    argument :head_sha, String, required: true

    field :pull_request, Types::PullRequestType, null: true
    field :errors, [String], null: false

    def resolve(owner:, name:, title:, body:, head_ref:, base_ref:, head_sha:)
      user = current_user!
      repository = Organization.find_by!(login: owner).repositories.find_by!(name:)
      authorize!(repository, :show?)

      pr = PullRequest.new(
        repository: repository,
        author: user,
        title: title,
        body: body,
        head_ref: head_ref,
        base_ref: base_ref,
        head_sha: head_sha,
        number: IssueNumberAllocator.next_for(repository),
        state: :open,
        mergeable_state: :mergeable
      )

      if pr.save
        { pull_request: pr, errors: [] }
      else
        { pull_request: nil, errors: pr.errors.full_messages }
      end
    rescue ActiveRecord::RecordNotFound
      { pull_request: nil, errors: ["Repository not found"] }
    end
  end
end
