module Types
  class MergeableStateEnum < Types::BaseEnum
    graphql_name "MergeableState"
    value "MERGEABLE", value: "mergeable"
    value "CONFLICT",  value: "conflict"
    value "MERGED",    value: "merged_state"
    value "CLOSED",    value: "closed_state"
  end
end
