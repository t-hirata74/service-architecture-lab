module Types
  class AggregatedCheckStateEnum < Types::BaseEnum
    graphql_name "AggregatedCheckState"

    value "SUCCESS", value: "success"
    value "FAILURE", value: "failure"
    value "PENDING", value: "pending"
    value "NONE",    value: "none"
  end
end
