module Types
  class MutationType < Types::BaseObject
    field :create_issue,  mutation: Mutations::CreateIssue
    field :close_issue,   mutation: Mutations::CloseIssue
    field :assign_issue,  mutation: Mutations::AssignIssue
    field :add_comment,   mutation: Mutations::AddComment
  end
end
