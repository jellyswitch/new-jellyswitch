class Api::V1::Admin::DoorsController < Api::V1::Admin::BaseController
  def index
    doors = Door.where(operator: current_tenant).order(:name)

    render json: doors.map { |d| door_json(d) }
  end

  def create
    door = Door.new(door_params)
    door.operator = current_tenant
    door.location = current_location

    if door.save
      render json: door_json(door), status: :created
    else
      render_error(door.errors.full_messages.join(', '))
    end
  end

  def update
    door = Door.find(params[:id])
    if door.update(door_params)
      render json: door_json(door)
    else
      render_error(door.errors.full_messages.join(', '))
    end
  end

  def archive
    door = Door.find(params[:id])
    door.update(available: false)
    render json: { success: true }
  end

  def unarchive
    door = Door.find(params[:id])
    door.update(available: true)
    render json: { success: true }
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

  def door_params
    params.permit(:name, :kisi_id, :slug, :private, :available)
  end

  def door_json(d)
    {
      id: d.id, name: d.name, kisi_id: d.kisi_id,
      slug: d.try(:slug), private: d.private, available: d.available,
    }
  end

  def unlock_door(door)
    url = "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
    HTTParty.post(url, headers: {
      "Authorization" => "KISI-LOGIN #{current_location.kisi_api_key}",
      "Content-type" => "application/json",
      "Accept" => "application/json",
    }).parsed_response
  end
end
