# ADR 0002: Org base / Team / 個人 collaborator から effective role を解く単一エントリポイント。
# Repository に対する有効ロールを返す。継承は「最大権限」を取る単純化。
class PermissionResolver
  ROLE_LEVELS = {
    none: 0,
    read: 1,
    triage: 2,
    write: 3,
    maintain: 4,
    admin: 5
  }.freeze
  ROLE_NAMES = ROLE_LEVELS.invert.freeze

  def initialize(user, repository)
    @user = user
    @repository = repository
  end

  # @return [Symbol] :none / :read / :triage / :write / :maintain / :admin
  def effective_role
    levels = [visibility_floor_level]
    if @user
      levels << base_role_level
      levels.concat(team_role_levels)
      levels << collaborator_role_level
    end

    ROLE_NAMES[levels.compact.max]
  end

  def can?(action)
    role_at_least?(MIN_REQUIRED[action] || :admin)
  end

  def role_at_least?(role)
    ROLE_LEVELS[effective_role] >= ROLE_LEVELS.fetch(role)
  end

  MIN_REQUIRED = {
    read: :read,
    comment: :read,
    triage: :triage,
    push: :write,
    create_issue: :read,
    assign_issue: :triage,
    request_review: :write,
    submit_review: :write,
    merge: :maintain,
    admin_repo: :admin
  }.freeze

  private

  # Org base role: outside_collaborator → :none(継承無し), member → :read, admin → :admin
  def base_role_level
    membership = Membership.find_by(organization_id: @repository.organization_id, user_id: @user.id)
    return ROLE_LEVELS[:none] unless membership

    case membership.role.to_sym
    when :admin then ROLE_LEVELS[:admin]
    when :member then ROLE_LEVELS[:read]
    else ROLE_LEVELS[:none] # outside_collaborator は base 継承なし
    end
  end

  def team_role_levels
    team_ids = TeamMember.where(user_id: @user.id)
                         .joins(:team)
                         .where(teams: { organization_id: @repository.organization_id })
                         .pluck(:team_id)
    return [] if team_ids.empty?

    TeamRepositoryRole.where(team_id: team_ids, repository_id: @repository.id)
                      .map { |trr| ROLE_LEVELS[trr.role.to_sym] }
  end

  def collaborator_role_level
    collab = RepositoryCollaborator.find_by(repository_id: @repository.id, user_id: @user.id)
    return ROLE_LEVELS[:none] unless collab

    ROLE_LEVELS[collab.role.to_sym]
  end

  # public_visibility なリポジトリは誰でも :read を持つ
  def visibility_floor_level
    return ROLE_LEVELS[:read] if @repository.public_visibility?

    ROLE_LEVELS[:none]
  end
end
