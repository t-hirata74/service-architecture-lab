# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :viewer, Types::UserType, null: true,
                   description: "Authenticated viewer. Null when unauthenticated."

    def viewer
      context[:current_user]
    end

    field :organization, Types::OrganizationType, null: true do
      argument :login, String, required: true
    end

    def organization(login:)
      Organization.find_by(login:)
    end

    field :repository, Types::RepositoryType, null: true do
      argument :owner, String, required: true
      argument :name, String, required: true
    end

    def repository(owner:, name:)
      org = Organization.find_by(login: owner)
      return nil unless org

      repo = org.repositories.find_by(name:)
      return nil unless repo

      # ADR 0002: read 権限が無いリソースは "存在しない" 扱い (404 同様の隠蔽)
      Pundit.policy(context[:current_user], repo).show? ? repo : nil
    end
  end
end
