module Types
  class IssueType < Types::BaseObject
    description "GitHub-style issue (ADR 0003)."

    field :id, ID, null: false
    field :number, Integer, null: false
    field :title, String, null: false
    field :body, String, null: false
    field :state, Types::IssueStateEnum, null: false
    field :author, Types::UserType, null: false
    field :assignees, [Types::UserType], null: false
    field :labels, [Types::LabelType], null: false
    field :comments, [Types::CommentType], null: false
    field :repository, Types::RepositoryType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
