module Types
  class IssueStateEnum < Types::BaseEnum
    graphql_name "IssueState"
    value "OPEN",   value: "open"
    value "CLOSED", value: "closed"
  end
end
