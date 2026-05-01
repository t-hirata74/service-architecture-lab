module Mutations
  # ADR 0001: action 単位 mutation。
  # ADR 0002 / 0003: read 権限以上で issue 作成可。番号は IssueNumberAllocator が払い出す。
  class CreateIssue < BaseMutation
    argument :owner, String, required: true
    argument :name, String, required: true
    argument :title, String, required: true
    argument :body, String, required: false, default_value: ""

    field :issue, Types::IssueType, null: true
    field :errors, [String], null: false

    def resolve(owner:, name:, title:, body:)
      user = current_user!
      repository = Organization.find_by!(login: owner).repositories.find_by!(name:)
      return { issue: nil, errors: ["Forbidden"] } unless authorize!(repository, :create_issue?, strict: false)

      issue = Issue.new(
        repository: repository,
        author: user,
        title: title,
        body: body,
        number: IssueNumberAllocator.next_for(repository),
        state: :open
      )

      if issue.save
        { issue: issue, errors: [] }
      else
        { issue: nil, errors: issue.errors.full_messages }
      end
    rescue ActiveRecord::RecordNotFound
      { issue: nil, errors: ["Repository not found"] }
    end
  end
end
