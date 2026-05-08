class AvailabilityRulesController < ApplicationController
  before_action :authenticate_host!

  def index
    rules = policy_scope(AvailabilityRule)
    render json: rules.map { |r| rule_json(r) }
  end

  def create
    rule = current_host.availability_rules.new(rule_params)
    authorize rule
    rule.save!
    render json: rule_json(rule), status: :created
  end

  def destroy
    rule = current_host.availability_rules.find(params[:id])
    authorize rule
    rule.destroy!
    head :no_content
  end

  private

  def rule_params
    params.permit(:event_type_id, :rrule, :start_time_of_day, :end_time_of_day,
                  :tz_id, :effective_from, :effective_until)
  end

  def rule_json(r)
    {
      id: r.id, host_id: r.host_id, event_type_id: r.event_type_id,
      rrule: r.rrule, tz_id: r.tz_id,
      start_time_of_day: r.start_time_of_day&.strftime("%H:%M:%S"),
      end_time_of_day:   r.end_time_of_day&.strftime("%H:%M:%S"),
      effective_from: r.effective_from, effective_until: r.effective_until
    }
  end
end
