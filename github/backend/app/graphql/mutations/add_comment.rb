module Mutations
  class AddComment < BaseMutation
    argument :issue_id, ID, required: true
    argument :body, String, required: true

    field :comment, Types::CommentType, null: true
    field :errors, [String], null: false

    def resolve(issue_id:, body:)
      user = current_user!
      issue = Issue.find_by(id: issue_id)
      return { comment: nil, errors: ["Issue not found"] } unless issue

      return { comment: nil, errors: ["Forbidden"] } unless authorize!(issue.repository, :comment?, strict: false)

      comment = issue.comments.create(author: user, body: body)
      if comment.persisted?
        { comment: comment, errors: [] }
      else
        { comment: nil, errors: comment.errors.full_messages }
      end
    end
  end
end
