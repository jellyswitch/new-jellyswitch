class Operator::NotificationsController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image

  def index
    @workflows = AutomatedWorkflow.where(operator: current_tenant, location: current_location)
    if @workflows.empty?
      AutomatedWorkflow.seed_defaults_for(current_tenant, location: current_location)
      @workflows = AutomatedWorkflow.where(operator: current_tenant, location: current_location)
    end
  end

  def reservations
    setting(:reservation_notifications)
  end

  def memberships
    setting(:membership_notifications)
  end

  def day_passes
    setting(:day_pass_notifications)
  end

  def signups
    setting(:signup_notifications)
  end

  def checkins
    setting(:checkin_notifications)
  end

  def paid_room_reservations
    setting(:paid_room_reservation_notifications)
  end

  def refunds
    setting(:refund_notifications)
  end

  def posts
    setting(:post_notifications)
  end

  def feedback
    setting(:member_feedback_notifications)
  end

  def toggle_workflow
    workflow = AutomatedWorkflow.find(params[:id])
    workflow.update!(enabled: !workflow.enabled)
    turbo_redirect(notifications_path, action: "replace")
  end

  private

  def setting(symbol)
    result = ToggleValue.call(object: current_tenant, value: symbol)

    if !result.success?
      flash[:error] = result.message
    end

    turbo_redirect(notifications_path, action: "replace")
  end
end