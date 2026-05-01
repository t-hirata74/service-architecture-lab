module Types
  class MutationType < Types::BaseObject
    field :create_issue,        mutation: Mutations::CreateIssue
    field :close_issue,         mutation: Mutations::CloseIssue
    field :assign_issue,        mutation: Mutations::AssignIssue
    field :add_comment,         mutation: Mutations::AddComment
    field :create_pull_request, mutation: Mutations::CreatePullRequest
    field :request_review,      mutation: Mutations::RequestReview
    field :submit_review,       mutation: Mutations::SubmitReview
    field :merge_pull_request,  mutation: Mutations::MergePullRequest
  end
end
