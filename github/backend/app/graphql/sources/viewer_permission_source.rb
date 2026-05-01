# ADR 0001: GraphQL N+1 を `GraphQL::Dataloader` で潰す。
# Repository ごとに 4 つの権限クエリ (membership / team / collaborator / repo) が走るのを、
# **viewer 単位で 1 度の問い合わせ**にまとめる。
#
# 使い方: `dataloader.with(Sources::ViewerPermissionSource, current_user).load(repository)`
module Sources
  class ViewerPermissionSource < GraphQL::Dataloader::Source
    ROLE_LEVELS = PermissionResolver::ROLE_LEVELS

    def initialize(user)
      @user = user
    end

    def fetch(repositories)
      repo_ids = repositories.map(&:id)
      org_ids  = repositories.map(&:organization_id).uniq
      visibility_floor = repositories.to_h do |r|
        [r.id, r.public_visibility? ? ROLE_LEVELS[:read] : ROLE_LEVELS[:none]]
      end

      base_levels   = base_role_levels(org_ids)
      team_levels   = team_role_levels(repo_ids)
      collab_levels = collaborator_role_levels(repo_ids)

      repositories.map do |repo|
        levels = [visibility_floor[repo.id]]
        if @user
          levels << (base_levels[repo.organization_id] || ROLE_LEVELS[:none])
          levels.concat(team_levels[repo.id] || [])
          levels << (collab_levels[repo.id] || ROLE_LEVELS[:none])
        end
        PermissionResolver::ROLE_NAMES[levels.compact.max]
      end
    end

    private

    # Org base role: outside_collaborator → :none / member → :read / admin → :admin
    def base_role_levels(org_ids)
      return {} unless @user

      Membership.where(organization_id: org_ids, user_id: @user.id)
                .each_with_object({}) do |m, h|
        h[m.organization_id] = case m.role.to_sym
                               when :admin then ROLE_LEVELS[:admin]
                               when :member then ROLE_LEVELS[:read]
                               else ROLE_LEVELS[:none]
                               end
      end
    end

    # 同じ user が複数 team から同じ repo に粒度違いで来うるので value は配列
    def team_role_levels(repo_ids)
      return {} unless @user

      team_ids = TeamMember.where(user_id: @user.id).pluck(:team_id)
      return {} if team_ids.empty?

      TeamRepositoryRole.where(team_id: team_ids, repository_id: repo_ids)
                        .each_with_object({}) do |trr, h|
        (h[trr.repository_id] ||= []) << ROLE_LEVELS[trr.role.to_sym]
      end
    end

    def collaborator_role_levels(repo_ids)
      return {} unless @user

      RepositoryCollaborator.where(repository_id: repo_ids, user_id: @user.id)
                            .each_with_object({}) do |rc, h|
        h[rc.repository_id] = ROLE_LEVELS[rc.role.to_sym]
      end
    end
  end
end
