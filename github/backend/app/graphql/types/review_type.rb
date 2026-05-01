module Types
  class ReviewType < Types::BaseObject
    field :id, ID, null: false
    field :state, Types::ReviewStateEnum, null: false
    field :body, String, null: false
    field :reviewer, Types::UserType, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
