class AvailabilityRulePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    resolver.owner?
  end

  def create?
    user.present? && (record.host_id.nil? || record.host_id == user.id)
  end

  def update?
    resolver.owner?
  end

  def destroy?
    resolver.owner?
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
