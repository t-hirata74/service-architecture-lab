class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_document, only: %i[show operations auto_layout lint]
  before_action :require_member!, only: %i[show operations auto_layout lint]

  def index
    docs = current_user.documents.order(:id)
    render json: docs.map { |d| document_summary(d) }
  end

  def create
    document = nil
    Document.transaction do
      document = Document.create!(name: params.require(:name), owner: current_user)
      DocumentMember.create!(document:, user: current_user, role: "owner")
    end
    render json: document_summary(document), status: :created
  end

  # snapshot: materialized な現在状態 + version (ADR 0002)。新規 join / リロードはこれを起点に
  # DocumentChannel を subscribe し、seq gap は GET :operations?since=N で補完する。
  def show
    render json: {
      document: document_summary(@document),
      version: @document.version,
      objects: @document.canvas_objects.alive.order(:z_index, :id).map { |o| object_json(o) }
    }
  end

  # catch-up: seq > since の op を昇順で返す (ADR 0002 / WS 取りこぼし吸収)。
  def operations
    since = params[:since].to_i
    ops = @document.operations.where("seq > ?", since).order(:seq)
    render json: ops.map { |op| op_json(op) }
  end

  # ai-worker proxy (Phase 4-2): 整列・分配の suggestion を返す。frontend が op 化して適用する。
  def auto_layout
    objects = @document.canvas_objects.alive.map { |o| geometry(o) }
    render json: AiWorkerClient.auto_layout(objects:, mode: params[:mode])
  end

  # ai-worker proxy (Phase 4-2): 重なり / グリッド外などの lint issue を返す。
  def lint
    objects = @document.canvas_objects.alive.map { |o| geometry(o) }
    render json: AiWorkerClient.lint(objects:, grid: params[:grid])
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def require_member!
    @role = @document.member_role(current_user.id)
    raise Forbidden if @role.nil?
  end

  def document_summary(document)
    {
      id: document.id,
      name: document.name,
      owner_id: document.owner_id,
      version: document.version,
      role: document.member_role(current_user.id)
    }
  end

  def object_json(object)
    {
      shape_id: object.shape_id,
      kind: object.kind,
      props: object.props,
      z_index: object.z_index,
      deleted: object.deleted
    }
  end

  def op_json(operation)
    {
      shape_id: operation.shape_id,
      op_type: operation.op_type,
      payload: operation.payload,
      lamport: operation.lamport,
      seq: operation.seq,
      actor_id: operation.actor_id,
      created_at: operation.created_at.iso8601
    }
  end

  # ai-worker に渡す最小ジオメトリ (props の数値だけ抜き出す)。
  def geometry(object)
    p = object.props
    {
      id: object.shape_id,
      x: p["x"].to_f, y: p["y"].to_f,
      w: (p["w"] || 0).to_f, h: (p["h"] || 0).to_f
    }
  end
end
