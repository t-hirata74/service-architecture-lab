module Types
  class CheckStateEnum < Types::BaseEnum
    graphql_name "CheckState"

    value "PENDING", value: "pending"
    value "SUCCESS", value: "success"
    value "FAILURE", value: "failure"
    value "ERROR",   value: "error"
  end
end
