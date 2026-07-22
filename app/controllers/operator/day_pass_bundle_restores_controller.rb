class Operator::DayPassBundleRestoresController < Operator::BaseController
  before_action :require_authentication

  # Admin "Restore a pass" — returns one pass to a member's Day Pass Bundle
  # (e.g. they burned it by accident). Auditable: who restored it, when, why.
  def create
    # Nested under /users/:user_id, so the param is the friendly_id slug.
    user   = current_tenant.users.friendly.find(params[:user_id])
    # acts_as_tenant scopes DayPassBundle.find to current_tenant automatically.
    # Also scope to the member to prevent restoring another user's bundle via this route.
    bundle = user.day_pass_bundles.find(params[:day_pass_bundle_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_day_passes_path(user),
                           alert: "Not authorized to restore a pass."
    end

    bundle.restore!(by: current_user, reason: params[:reason].presence)

    redirect_back fallback_location: user_day_passes_path(user),
                  notice: "Restored a pass to #{user.name}'s bundle."
  end
end
