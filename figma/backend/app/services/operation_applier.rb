# OperationApplier — figma の中核 (ADR 0001 / 0002)。
#
# 1 つの編集 op を 1 トランザクションで適用する:
#   1. document.next_seq! で server 権威の総順序 seq を with_lock 採番 (= documents.version)。
#      この document 行ロックが同一ドキュメントへの並行 op を直列化し、canvas_objects への
#      並行書き込みを構造的に防ぐ (ADR 0002 のトレードオフ「version lock 競合」)。
#   2. operations に append (append-only ordered log)。
#   3. canvas_objects を per-property LWW-Register で materialize:
#      各プロパティを (lamport, actor_id) で比較し、incoming が stored より新しいときだけ採用。
#      tie は actor_id で決定的に決める。これにより「op を任意の順で適用しても同一状態に収束」する
#      = CRDT 収束性 (spec/services/operation_applier_spec.rb で不変条件を固定)。
#
# 2 つの時計を分ける (ADR 0001):
#   - seq    : 配信安定化 / catch-up / dedup 用の server 採番総順序。収束には関与しない。
#   - lamport: LWW 勝敗判定用の client 論理時計。到着順・seq に依存しない収束を保証する。
class OperationApplier
  Result = Struct.new(:operation, :object, :applied_props, keyword_init: true)

  class InvalidOperation < StandardError; end

  PLACEHOLDER_KIND = "rect" # out-of-order (create より先に update が来た) 時の仮 kind。create が後で上書きする。

  def self.call(document:, actor:, shape_id:, op_type:, payload:, lamport:)
    new(document:, actor:, shape_id:, op_type:, payload:, lamport:).call
  end

  def initialize(document:, actor:, shape_id:, op_type:, payload:, lamport:)
    @document = document
    @actor = actor
    @shape_id = shape_id.to_s
    @op_type = op_type.to_s
    @payload = normalize_payload(payload)
    @lamport = coerce_lamport(lamport)
  end

  def call
    validate!
    @document.transaction do
      seq = @document.next_seq!
      operation = Operation.create!(
        document: @document, actor: @actor, shape_id: @shape_id,
        op_type: @op_type, payload: @payload, lamport: @lamport,
        seq: seq, created_at: Time.current
      )
      object, applied = materialize!(seq)
      Result.new(operation:, object:, applied_props: applied)
    end
  end

  private

  attr_reader :document, :actor, :shape_id, :op_type, :payload, :lamport

  def materialize!(seq)
    object = document.canvas_objects.find_or_initialize_by(shape_id: shape_id)
    if object.new_record?
      object.kind = create_kind || PLACEHOLDER_KIND
      object.props = {}
      object.prop_clocks = {}
    elsif op_type == "create" && create_kind
      # create の再配信 / out-of-order create: kind は create が唯一の設定者なので上書きする。
      object.kind = create_kind
    end

    props = object.props.dup
    clocks = object.prop_clocks.dup
    applied = []

    lww_payload.each do |key, value|
      stored = clocks[key]
      next unless newer?(lamport, actor.id, stored)

      props[key] = value
      clocks[key] = { "l" => lamport, "a" => actor.id }
      applied << key
    end

    object.props = props
    object.prop_clocks = clocks
    object.deleted = (props["deleted"] == true)
    object.z_index = props["z_index"].to_i if props.key?("z_index")
    object.last_seq = seq
    object.save!
    [ object, applied ]
  end

  # LWW 比較: incoming (lamport, actor_id) が stored clock より新しいか。
  # stored が無ければ常に採用。lamport が同値なら actor_id で tie-break (決定的)。
  def newer?(incoming_l, incoming_a, stored)
    return true if stored.nil?
    return incoming_l > stored["l"] if incoming_l != stored["l"]

    incoming_a > stored["a"]
  end

  # canvas に LWW 適用するプロパティ集合。kind は LWW しない (create 専管) ので除外。
  # delete は "deleted" プロパティへの LWW op として表現する (create/update/delete を統一機構に)。
  def lww_payload
    base = payload.except("kind")
    op_type == "delete" ? base.merge("deleted" => true) : base
  end

  def create_kind
    return nil unless op_type == "create"

    payload["kind"].presence
  end

  def validate!
    unless Operation::OP_TYPES.include?(op_type)
      raise InvalidOperation, "unknown op_type: #{op_type.inspect}"
    end
    raise InvalidOperation, "lamport must be positive" unless lamport.positive?
    raise InvalidOperation, "shape_id required" if shape_id.blank?

    if op_type == "create" && !CanvasObject::KINDS.include?(create_kind)
      raise InvalidOperation, "create requires kind in #{CanvasObject::KINDS.inspect}"
    end
  end

  def normalize_payload(payload)
    case payload
    when Hash then payload.deep_stringify_keys
    when nil then {}
    else raise InvalidOperation, "payload must be an object"
    end
  end

  def coerce_lamport(lamport)
    Integer(lamport)
  rescue ArgumentError, TypeError
    raise InvalidOperation, "lamport must be an integer"
  end
end
