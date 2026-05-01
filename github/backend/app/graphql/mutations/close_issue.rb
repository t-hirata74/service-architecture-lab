module Mutations
  class CloseIssue < BaseMutation
    argument :issue_id, ID, required: true

    field :issue, Types::IssueType, null: true
    field :errors, [String], null: false

    def resolve(issue_id:)
      current_user!
      issue = Issue.find_by(id: issue_id)
      return { issue: nil, errors: ["Issue not found"] } unless issue

      return { issue: nil, errors: ["Forbidden"] } unless authorize!(issue.repository, :close_issue?, strict: false)

      issue.close!
      { issue: issue, errors: [] }
    end
  end
end
