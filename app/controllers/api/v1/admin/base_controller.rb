class Api::V1::Admin::BaseController < Api::V1::BaseController
  before_action :require_admin!
  before_action :enforce_location_scope!

  private

  def require_admin!
    unless admin_user?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end

  # Staff who may use the admin API. Uses the User role predicates rather than
  # raw strings: the role values are hyphenated ("general-manager"), so the old
  # `role.in?(%w[admin general_manager community_manager])` only ever matched
  # "admin" and silently locked out general/community managers who didn't also
  # have the `admin` boolean set. Mirrors the roles granted admin views in
  # ReportPolicy (admin / superadmin / general-manager), plus community managers.
  def admin_user?
    u = current_api_user
    return false unless u

    u.admin? || u.superadmin? || u.general_manager? || u.community_manager?
  end

  # Cross-LOCATION boundary for the admin API. (Cross-tenant is enforced for the
  # whole API in Api::V1::BaseController#enforce_tenant_scope!.) Non-superadmins
  # are confined to the locations they manage plus their own home location;
  # `current_location` follows the caller's own record, so without this a switch
  # to an unmanaged location would expose its data. ANY superadmin? (boolean OR
  # the per-operator role) sees every location in the operator, mirroring
  # User#admin_of_location?.
  def enforce_location_scope!
    return if current_api_user&.superadmin?

    location = current_location
    return if location.nil?

    allowed_location_ids = current_api_user.managed_location_ids + [current_api_user.original_location_id].compact
    render json: { error: 'Forbidden' }, status: :forbidden unless allowed_location_ids.include?(location.id)
  end
end
