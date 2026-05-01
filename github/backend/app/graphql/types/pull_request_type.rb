module Types
  class PullRequestType < Types::BaseObject
    description "Pull request shares the issue/PR number space (ADR 0003)."

    field :id, ID, null: false
    field :number, Integer, null: false
    field :title, String, null: false
    field :body, String, null: false
    field :state, Types::PullRequestStateEnum, null: false
    field :mergeable_state, Types::MergeableStateEnum, null: false
    field :head_ref, String, null: false
    field :base_ref, String, null: false
    field :head_sha, String, null: false
    field :author, Types::UserType, null: false
    field :repository, Types::RepositoryType, null: false
    field :reviews, [Types::ReviewType], null: false
    field :requested_reviewers, [Types::UserType], null: false
    field :comments, [Types::CommentType], null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def requested_reviewers
      object.reviewers_requested
    end
  end
end
