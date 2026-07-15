class Api::V1::Admin::DoorsController < Api::V1::Admin::BaseController
  # Scope the by-id lookups to the caller's operator. Without this, a bare
  # Door.find(params[:id]) is GLOBAL in the API (the acts_as_scopable tenant
  # default_scope is only installed by the web Operator::BaseController, never
  # in the API stack), so staff at any operator could tamper with — or read the
  # entry log of — another tenant's doors by walking door ids.
  before_action :set_door, only: %i[update archive unarchive open punches]

  def index
    doors = Door.where(operator: current_tenant).includes(:beacons).order(:name)

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
    if @door.update(door_params)
      render json: door_json(@door)
    else
      render_error(@door.errors.full_messages.join(', '))
    end
  end

  def archive
    @door.update(available: false)
    render json: { success: true }
  end

  def unarchive
    @door.update(available: true)
    render json: { success: true }
  end

  def open
    begin
      response = unlock_door(@door)
      # Staff-only controller, so no room-lock authorization needed — but a
      # Room Lock open is still a Room Entry, never a building entry (ADR 0021).
      DoorPunch.create(user: current_api_user, door: @door, operator: current_tenant, json: response,
                       room_entry: @door.room_lock?)
      render json: { success: true, door: @door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: @door.name, message: e.message }
    end
  end

  def punches
    punches = DoorPunch.where(door_id: @door.id).order(created_at: :desc).limit(30)

    render json: punches.map { |p|
      {
        id: p.id,
        user_name: p.user&.name,
        created_at: p.created_at.iso8601,
      }
    }
  end

  private

  def set_door
    @door = current_tenant.doors.find_by(id: params[:id])
    render_error("Door not found", status: :not_found) unless @door
  end

  def door_params
    params.permit(:name, :kisi_id, :slug, :private, :available)
  end

  def door_json(d)
    {
      id: d.id, name: d.name, kisi_id: d.kisi_id,
      slug: d.try(:slug), private: d.private, available: d.available,
      # Attached room ⇒ this door is a Room Lock (ADR 0021).
      room_id: d.room_id, room_name: d.room&.name,
      # Beacon-linked ⇒ arrival-unlock building entrance; the room picker
      # confirms before letting it be attached as a room lock.
      beacon: d.beacons.any?,
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
