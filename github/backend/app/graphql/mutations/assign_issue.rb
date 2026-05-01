module Mutations
  class AssignIssue < BaseMutation
    argument :issue_id, ID, required: true
    argument :assignee_logins, [String], required: true

    field :issue, Types::IssueType, null: true
    field :errors, [String], null: false

    def resolve(issue_id:, assignee_logins:)
      current_user!
      issue = Issue.find_by(id: issue_id)
      return { issue: nil, errors: ["Issue not found"] } unless issue

      return { issue: nil, errors: ["Forbidden"] } unless authorize!(issue.repository, :assign_issue?, strict: false)

      users = User.where(login: assignee_logins).to_a
      missing = assignee_logins - users.map(&:login)
      return { issue: nil, errors: ["Unknown logins: #{missing.join(', ')}"] } if missing.any?

      Issue.transaction do
        issue.issue_assignees.destroy_all
        users.each { |u| issue.issue_assignees.create!(user: u) }
      end

      { issue: issue.reload, errors: [] }
    end
  end
end
