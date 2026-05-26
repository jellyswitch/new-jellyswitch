class Api::LocationsController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_api_user

  def index
    # Return locations with coordinates for geofencing
    user = current_user
    locations = if user&.current_location
      [user.current_location]
    elsif user&.original_location
      [user.original_location]
    else
      []
    end

    # Include all operator locations if user has access to multiple
    if current_tenant
      # Scope to .visible so geofencing doesn't trigger door-unlock UI for
      # hidden locations (test scratchpads, archived spaces).
      locations = current_tenant.locations.visible.where.not(latitude: nil, longitude: nil)
    end

    render json: locations.map { |loc|
      {
        id: loc.id,
        name: loc.name,
        latitude: loc.latitude&.to_f,
        longitude: loc.longitude&.to_f,
        has_doors: loc.doors.available.any?,
        geofence_radius: 50
      }
    }
  end

  private

  def authenticate_api_user
    unless current_user
      render json: { error: "Unauthorized" }, status: 401
    end
  end
end
