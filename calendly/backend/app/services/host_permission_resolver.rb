# 認可の中核 (PORO)。github / zoom と同形の 2 層構造の下層。
# Pundit policy はこの Resolver を呼ぶだけにし、controller / job からも再利用可能。
#
# calendly の認可モデルは zoom より単純:
# - host: 自分の event_type / availability_rule / busy_period / booking を CRUD
# - invitee: guest として booking を作成 / 自分が作った booking のキャンセルだけ可能
#   (本リポでは invitee 認証は実装しないため、controller 側で email 一致のみ確認)
class HostPermissionResolver
  def initialize(host, record)
    @host = host
    @record = record
  end

  # event_type / availability_rule / busy_period / booking が host のものか。
  # review fix M-D-1: case 文の型判定 → duck typing (`respond_to?(:host_id)`) に変更。
  # 新規 host-scoped リソース追加時に Resolver の更新が不要になる。
  def owner?
    return false if @host.nil?
    return @record.id == @host.id if @record.is_a?(Host)
    return @record.host_id == @host.id if @record.respond_to?(:host_id)
    false
  end

  # 公開 event_type は誰でも slot 取得 / 予約可能
  def public_visible?
    return false unless @record.is_a?(EventType)
    @record.active?
  end

  def can_manage?
    owner?
  end

  def can_view?
    owner? || public_visible?
  end
end
