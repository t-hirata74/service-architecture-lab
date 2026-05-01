module Types
  class RepositoryVisibilityEnum < Types::BaseEnum
    value "PRIVATE",  value: "private_visibility"
    value "INTERNAL", value: "internal_visibility"
    value "PUBLIC",   value: "public_visibility"
  end
end
