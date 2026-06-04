class DocumentMembersController < ApplicationController
  before_action :authenticate_user!

  # collaborator 追加。owner のみ可 (ADR 0004)。
  def create
    document = Document.find(params[:document_id])
    raise Forbidden unless document.member_role(current_user.id) == "owner"

    user = User.find(params.require(:user_id))
    role = params[:role].presence || "editor"
    member = DocumentMember.create!(document:, user:, role:)
    render json: { document_id: document.id, user_id: user.id, role: member.role }, status: :created
  end
end
