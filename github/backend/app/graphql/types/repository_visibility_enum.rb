module Types
  class RepositoryVisibilityEnum < Types::BaseEnum
    graphql_name "RepositoryVisibility"
    value "PRIVATE",  value: "private_visibility"
    value "INTERNAL", value: "internal_visibility"
    value "PUBLIC",   value: "public_visibility"
  end
end
