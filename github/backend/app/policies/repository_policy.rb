class RepositoryPolicy < ApplicationPolicy
  def show?
    resolver.role_at_least?(:read)
  end

  def push?
    resolver.can?(:push)
  end

  def admin?
    resolver.can?(:admin_repo)
  end

  def viewer_permission
    resolver.effective_role
  end

  class Scope < Scope
    def resolve
      return scope.where(visibility: Repository.visibilities[:public_visibility]) if user.nil?

      org_ids = Membership.where(user_id: user.id).pluck(:organization_id)
      collaborator_repo_ids = RepositoryCollaborator.where(user_id: user.id).pluck(:repository_id)
      team_repo_ids = TeamRepositoryRole.where(team_id: user.team_members.pluck(:team_id)).pluck(:repository_id)

      scope.where(
        "organization_id IN (?) OR id IN (?) OR id IN (?) OR visibility = ?",
        org_ids,
        collaborator_repo_ids,
        team_repo_ids,
        Repository.visibilities[:public_visibility]
      )
    end
  end

  private

  def resolver
    @resolver ||= PermissionResolver.new(user, record)
  end
end
