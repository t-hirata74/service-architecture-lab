module Types
  class RepositoryType < Types::BaseObject
    description "GitHub-style repository (ADR 0002 / 0003)."

    field :id, ID, null: false
    field :name, String, null: false
    field :description, String, null: true
    field :visibility, Types::RepositoryVisibilityEnum, null: false
    field :owner, Types::OrganizationType, null: false
    field :viewer_permission, Types::RepositoryPermissionEnum, null: false,
          description: "Effective role of the current viewer (ADR 0002)."

    def owner
      object.organization
    end

    def viewer_permission
      PermissionResolver.new(context[:current_user], object).effective_role
    end
  end
end
