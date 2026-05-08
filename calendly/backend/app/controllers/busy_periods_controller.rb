class BusyPeriodsController < ApplicationController
  before_action :authenticate_host!

  def index
    periods = current_host.busy_periods.order(:start_at)
    render json: periods.map { |p| period_json(p) }
  end

  def create
    bp = current_host.busy_periods.new(bp_params)
    bp.save!
    render json: period_json(bp), status: :created
  end

  def destroy
    bp = current_host.busy_periods.find(params[:id])
    bp.destroy!
    head :no_content
  end

  private

  def bp_params
    params.permit(:start_at, :end_at, :source, :external_id)
  end

  def period_json(bp)
    {
      id: bp.id, start_at: bp.start_at.iso8601, end_at: bp.end_at.iso8601,
      source: bp.source, external_id: bp.external_id
    }
  end
end
