class BookingPolicy < ApplicationPolicy
  # host が自分宛の booking を一覧 / 個別表示できる。
  def index?
    user.present?
  end

  def show?
    resolver.owner?
  end

  # 予約作成は guest invitee も含めて誰でも (controller 側で event_type.active を弾く)
  def create?
    true
  end

  # キャンセルは host 側 + 一致する invitee_email (controller で渡される)
  def destroy?
    resolver.owner? || invitee_match?
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

  # `record` が Booking の場合、controller が `record.invitee_email_matches?(email)` を呼ぶ前提で
  # ここでは host 一致だけ判定。invitee 側のキャンセル UI は controller で email 一致を別途確認する。
  def invitee_match?
    false
  end
end
