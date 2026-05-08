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

  # event_type / availability_rule / busy_period / booking が host のものか
  def owner?
    return false if @host.nil?
    case @record
    when EventType, AvailabilityRule, BusyPeriod, Booking
      @record.host_id == @host.id
    when Host
      @record.id == @host.id
    else
      false
    end
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
