class Api::V1::DoorsController < Api::V1::BaseController
  include Api::V1::DoorUnlocking

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
    door     = Door.find(params[:id])
    location = current_location
    user     = current_api_user

    unless user_can_access_building?(user, location)
      return render json: {
        success: false,
        door:    door.name,
        message: "You don't have access today. Buy a day pass or activate a membership to unlock the doors.",
      }, status: :forbidden
    end

    begin
      perform_unlock(door: door, user: user, location: location, method: "manual")
      render json: { success: true, door: door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end
end
