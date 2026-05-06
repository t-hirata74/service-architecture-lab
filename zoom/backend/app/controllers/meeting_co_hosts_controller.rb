# Phase 4-1: ADR 0002 — 共同ホストの指名 / 取り消し。指名は host のみ。
class MeetingCoHostsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_meeting

  # POST /meetings/:meeting_id/co_hosts { user_id }
  def create
    authorize @meeting, :grant_co_host?
    co_host = @meeting.meeting_co_hosts.create!(
      user_id: params.fetch(:user_id),
      granted_by_user: current_user
    )
    render json: { id: co_host.id, user_id: co_host.user_id }, status: :created
  end

  # DELETE /meetings/:meeting_id/co_hosts/:id (id = user_id)
  def destroy
    authorize @meeting, :revoke_co_host?
    co_host = @meeting.meeting_co_hosts.find_by!(user_id: params.fetch(:id))
    co_host.destroy!
    head :no_content
  end

  private

  def load_meeting
    @meeting = Meeting.find(params[:meeting_id])
  end
end
