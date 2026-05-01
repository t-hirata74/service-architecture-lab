module Types
  class ReviewStateEnum < Types::BaseEnum
    graphql_name "ReviewState"
    value "COMMENTED",         value: "commented"
    value "APPROVED",          value: "approved"
    value "CHANGES_REQUESTED", value: "changes_requested"
  end
end
