class RepositoryPolicy < ApplicationPolicy
  # ADR 0002: 認可は GraphQL resolver / mutation から **Pundit policy 経由**で呼ぶ。
  # 役割の最大値解決は PermissionResolver、verb への束縛はここに集約する。
  # Mutation 側で `PermissionResolver.new(user, repo).role_at_least?(:write)` を直書きしない。

  def show?
    resolver.role_at_least?(:read)
  end

  def create_issue?
    resolver.can?(:create_issue)
  end

  def comment?
    resolver.can?(:comment)
  end

  def assign_issue?
    resolver.can?(:assign_issue)
  end

  def close_issue?
    resolver.can?(:assign_issue) # close と assign は同じ triage 階層 (ADR 0002 MIN_REQUIRED)
  end

  def create_pull_request?
    resolver.role_at_least?(:read)
  end

  def request_review?
    resolver.can?(:request_review)
  end

  def submit_review?
    resolver.can?(:submit_review)
  end

  def merge_pull_request?
    resolver.can?(:merge)
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

      # ADR 0002: outside_collaborator は org base 継承を持たない (= 個別付与だけが視認の根拠)
      inheriting_roles = [Membership.roles[:member], Membership.roles[:admin]]
      org_ids = Membership.where(user_id: user.id, role: inheriting_roles).pluck(:organization_id)
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
