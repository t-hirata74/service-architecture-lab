class EventTypePolicy < ApplicationPolicy
  def show?
    resolver.can_view?
  end

  def create?
    resolver.owner? || record.host_id.nil?  # new record で host_id 未設定もホスト側操作扱い
  end

  def update?
    resolver.can_manage?
  end

  def destroy?
    resolver.can_manage?
  end

  # invitee 公開ページ (public)。資源側の `active` フラグだけで判定。
  def public_show?
    record.active?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.nil?
      scope.where(host_id: user.id)
    end
  end

  private

  def resolver
    HostPermissionResolver.new(user, record)
  end
end
