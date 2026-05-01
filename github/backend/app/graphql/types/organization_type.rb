module Types
  class OrganizationType < Types::BaseObject
    description "Organization owns repositories and teams (ADR 0002)."

    field :id, ID, null: false
    field :login, String, null: false
    field :name, String, null: false
    field :repositories, [Types::RepositoryType], null: false

    def repositories
      RepositoryPolicy::Scope.new(context[:current_user], object.repositories).resolve
    end
  end
end
