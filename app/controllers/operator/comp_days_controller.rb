class Operator::CompDaysController < Operator::BaseController
  before_action :require_authentication

  # Admin "Comp a day" — returns one day to a member's Day Pool for the current
  # period (e.g. the door reader was down). Auditable: who granted it, when, why.
  def create
    # Nested under /users/:user_id, so the param is the friendly_id slug.
    user = current_tenant.users.friendly.find(params[:user_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_path(user), alert: "Not authorized to comp a day."
    end

    CompDay.create!(
      user: user,
      operator: current_tenant,
      location: current_location,
      granted_by: current_user,
      occurred_on: Date.current,
      reason: params[:reason].presence,
    )

    redirect_back fallback_location: user_path(user),
                  notice: "Comped a day back to #{user.name} for this period."
  end
end
