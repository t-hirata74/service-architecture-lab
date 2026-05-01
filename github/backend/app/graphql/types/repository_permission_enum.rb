module Types
  class RepositoryPermissionEnum < Types::BaseEnum
    description "Effective permission level a viewer holds on a repository."

    value "NONE",     value: :none
    value "READ",     value: :read
    value "TRIAGE",   value: :triage
    value "WRITE",    value: :write
    value "MAINTAIN", value: :maintain
    value "ADMIN",    value: :admin
  end
end
