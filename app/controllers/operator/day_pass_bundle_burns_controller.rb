class Operator::DayPassBundleBurnsController < Operator::BaseController
  before_action :require_authentication

  # Admin "Burn a pass" — spends one pass from a member's Day Pass Bundle with
  # no date attached (e.g. an entry the door system missed). Auditable via the
  # admin_burn redemption row; no DayPass is minted, so nothing here grants
  # door access or reservation coverage.
  def create
    # friendly.find: nested user routes carry the friendly_id slug, not the id.
    user   = current_tenant.users.friendly.find(params[:user_id])
    # acts_as_tenant scopes DayPassBundle.find to current_tenant automatically.
    # Also scope to the member to prevent burning another user's bundle via this route.
    bundle = user.day_pass_bundles.find(params[:day_pass_bundle_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_day_passes_path(user),
                           alert: "Not authorized to burn a pass."
    end

    bundle.burn!(kind: :admin_burn, performed_by: current_user,
                 guest_name: params[:reason].presence)

    redirect_back fallback_location: user_day_passes_path(user),
                  notice: "Burned a pass from #{user.name}'s bundle."
  rescue DayPassBundle::NoPassesRemaining
    redirect_back fallback_location: user_day_passes_path(user),
                  alert: "No passes left in that bundle."
  end
end
