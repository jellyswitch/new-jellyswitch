class Api::V1::Admin::DoorsController < Api::V1::Admin::BaseController
  def index
    doors = Door.where(operator: current_tenant).order(:name)

    render json: doors.map { |d|
      {
        id: d.id,
        name: d.name,
        kisi_id: d.kisi_id,
        private: d.private,
        available: d.available,
      }
    }
  end

  def open
    door = Door.find(params[:id])

    begin
      response = unlock_door(door)
      DoorPunch.create(user: current_api_user, door: door, operator: current_tenant, json: response)
      render json: { success: true, door: door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end

  def punches
    punches = DoorPunch.where(door_id: params[:id]).order(created_at: :desc).limit(30)

    render json: punches.map { |p|
      {
        id: p.id,
        user_name: p.user&.name,
        created_at: p.created_at.iso8601,
      }
    }
  end

  private

  def unlock_door(door)
    url = "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
    HTTParty.post(url, headers: {
      "Authorization" => "KISI-LOGIN #{current_location.kisi_api_key}",
      "Content-type" => "application/json",
      "Accept" => "application/json",
    }).parsed_response
  end
end
