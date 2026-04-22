class Api::V1::DoorsController < Api::V1::BaseController
  include DoorsHelper

  def index
    location = current_location
    return render json: [] unless location

    doors = location.doors.where(available: true)
    doors = doors.where(private: false) unless current_api_user.admin?

    render json: doors.map { |d| { id: d.id, name: d.name, private: d.private } }
  end

  def punches
    door = Door.find(params[:id])
    punches = DoorPunch.where(door: door, user: current_api_user)
      .order(created_at: :desc)
      .limit(30)

    render json: punches.map { |p|
      {
        id: p.id,
        door_name: door.name,
        timestamp: p.created_at.strftime("%B %e, %Y at %l:%M %p"),
      }
    }
  end

  def unlock
    door = Door.find(params[:id])
    location = current_location
    user = current_api_user

    unless user_can_access_building?(user, location)
      return render json: {
        success: false,
        door: door.name,
        message: "You don't have access today. Buy a day pass or activate a membership to unlock the doors.",
      }, status: :forbidden
    end

    # Log the attempt
    DoorPunch.create(user: user, door: door, operator: current_tenant)

    # Call Kisi API
    begin
      response = unlock_door(door, location)
      DoorPunch.create(user: user, door: door, operator: current_tenant, json: response)
      render json: { success: true, door: door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end

  private

  def user_can_access_building?(user, location)
    return false if user.nil?
    # Admins/managers/superadmin always.
    return true if user.superadmin?
    return true if location && user.admin_or_manager?(location)
    # Active coverage today.
    zone = location&.time_zone.presence || 'UTC'
    today = Time.current.in_time_zone(zone).to_date
    return true if user.has_active_subscription?
    return true if user.day_passes.where(day: today).any?
    return true if location && user.has_active_lease?(location)
    false
  end

  def unlock_door(door, location)
    url = "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
    HTTParty.post(url, headers: {
      "Authorization" => "KISI-LOGIN #{location.kisi_api_key}",
      "Content-type" => "application/json",
      "Accept" => "application/json",
    }).parsed_response
  end
end
