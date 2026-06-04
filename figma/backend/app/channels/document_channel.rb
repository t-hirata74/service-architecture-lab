# ADR 0003: document 単位の購読 + op fan-out + ephemeral cursor。
# slack の MessagesChannel が「append-only message の fan-out」なのに対し、こちらは
# 「収束する op の fan-out」(server で LWW 適用 → seq 付きで broadcast)。
class DocumentChannel < ApplicationCable::Channel
  def subscribed
    @document = Document.find_by(id: params[:document_id])
    return reject if @document.nil?

    @role = @document.member_role(current_user.id)
    return reject if @role.nil? # 非 member は購読拒否 (ADR 0004 第1段)

    stream_for @document
  end

  # client → server: 編集 op を適用 (ADR 0001/0002)。viewer は拒否 (ADR 0004 第2段)。
  def apply_operation(data)
    return transmit_error("forbidden") unless can_edit?

    result = OperationApplier.call(
      document: @document,
      actor: current_user,
      shape_id: data["shape_id"],
      op_type: data["op_type"],
      payload: data["payload"] || {},
      lamport: data["lamport"]
    )
    DocumentChannel.broadcast_to(@document, operation_message(result.operation))
  rescue OperationApplier::InvalidOperation => e
    transmit_error("invalid_operation", e.message)
  end

  # client → server: cursor 位置を ephemeral に fan-out (DB に触れない、ADR 0003)。
  def cursor(data)
    DocumentChannel.broadcast_to(@document, {
      type: "cursor",
      actor_id: current_user.id,
      name: current_user.name,
      x: data["x"],
      y: data["y"]
    })
  end

  private

  def can_edit?
    @role == "owner" || @role == "editor"
  end

  def operation_message(operation)
    {
      type: "operation",
      op: {
        shape_id: operation.shape_id,
        op_type: operation.op_type,
        payload: operation.payload,
        lamport: operation.lamport,
        seq: operation.seq,
        actor_id: operation.actor_id
      }
    }
  end

  def transmit_error(code, message = nil)
    transmit({ type: "error", code: code, message: message }.compact)
  end
end
