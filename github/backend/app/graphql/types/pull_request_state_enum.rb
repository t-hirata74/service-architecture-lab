module Types
  class PullRequestStateEnum < Types::BaseEnum
    graphql_name "PullRequestState"
    value "OPEN",   value: "open"
    value "CLOSED", value: "closed"
    value "MERGED", value: "merged"
  end
end
