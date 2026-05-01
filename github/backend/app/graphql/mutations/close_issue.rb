module Mutations
  class CloseIssue < BaseMutation
    argument :issue_id, ID, required: true

    field :issue, Types::IssueType, null: true
    field :errors, [String], null: false

    def resolve(issue_id:)
      current_user!
      issue = Issue.find_by(id: issue_id)
      return { issue: nil, errors: ["Issue not found"] } unless issue

      # ADR 0002 MIN_REQUIRED[:assign_issue] == :triage; close も :triage 以上
      resolver = PermissionResolver.new(context[:current_user], issue.repository)
      unless resolver.role_at_least?(:triage)
        return { issue: nil, errors: ["Forbidden"] }
      end

      issue.close!
      { issue: issue, errors: [] }
    end
  end
end
