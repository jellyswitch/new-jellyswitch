class Operator::Admin::AutomatedWorkflowsController < Operator::BaseController
  before_action :background_image, only: [:index]

  def index
    authorize :automated_workflow, :index?
    AutomatedWorkflow.seed_defaults_for(current_tenant, location: current_location)
    @workflows = current_tenant.automated_workflows
                               .where(location: current_location)
                               .order(:workflow_type)
  end

  def update
    workflow = current_tenant.automated_workflows.find(params[:id])
    authorize workflow, :update?

    merged_config = workflow.config.merge(parse_config_params(workflow))
    attrs = { config: merged_config }
    if params.dig(:automated_workflow, :enabled).present?
      attrs[:enabled] = ActiveModel::Type::Boolean.new.cast(params.dig(:automated_workflow, :enabled))
    end

    if workflow.update(attrs)
      flash[:success] = "#{workflow.human_name} updated."
    else
      flash[:error] = workflow.errors.full_messages.to_sentence
    end

    turbo_redirect(automated_workflows_path)
  end

  private

  def parse_config_params(workflow)
    raw = params.dig(:automated_workflow, :config) || {}
    case workflow.workflow_type
    when "re_engagement"
      raw[:days_inactive].present? ? { "days_inactive" => raw[:days_inactive].to_i } : {}
    when "past_due_followup"
      list = parse_int_list(raw[:followup_days])
      list.present? ? { "followup_days" => list } : {}
    when "booking_reminder"
      raw[:hours_before].present? ? { "hours_before" => raw[:hours_before].to_i } : {}
    when "day_passer_followup", "room_reservation_followup"
      raw[:days_after].present? ? { "days_after" => raw[:days_after].to_i } : {}
    when "past_member_recovery"
      raw[:days_after_grace].present? ? { "days_after_grace" => raw[:days_after_grace].to_i } : {}
    else
      {}
    end
  end

  def parse_int_list(value)
    return nil if value.blank?
    value.to_s.split(",").map { |n| n.strip.to_i }.reject(&:zero?)
  end
end
