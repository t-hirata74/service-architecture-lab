module Types
  class CommitCheckType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :state, Types::CheckStateEnum, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true
    field :output, String, null: true
  end
end
