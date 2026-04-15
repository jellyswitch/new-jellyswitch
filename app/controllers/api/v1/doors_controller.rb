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

    # Log the attempt
    DoorPunch.create(user: current_api_user, door: door, operator: current_tenant)

    # Call Kisi API
    begin
      response = unlock_door(door, current_location)
      DoorPunch.create(user: current_api_user, door: door, operator: current_tenant, json: response)
      render json: { success: true, door: door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end

  private

  def unlock_door(door, location)
    url = "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
    HTTParty.post(url, headers: {
      "Authorization" => "KISI-LOGIN #{location.kisi_api_key}",
      "Content-type" => "application/json",
      "Accept" => "application/json",
    }).parsed_response
  end
end
