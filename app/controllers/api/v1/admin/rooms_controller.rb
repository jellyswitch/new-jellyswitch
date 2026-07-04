class Api::V1::Admin::RoomsController < Api::V1::Admin::BaseController
  def index
    rooms = Room.where(operator: current_tenant)
    rooms = if params[:archived] == 'true'
              rooms.archived
            elsif params[:archived] == 'all'
              rooms
            else
              rooms.active
            end
    rooms = rooms.order(:name)

    render json: rooms.map { |room| room_json(room) }
  end

  def create
    room = Room.new(room_params)
    room.operator = current_tenant
    room.location = current_location

    if room.save
      render json: room_json(room), status: :created
    else
      render_error(room.errors.full_messages.join(', '))
    end
  end

  def update
    room = Room.find(params[:id])

    if params[:room]&.key?(:door_ids)
      room.reassign_doors!(params[:room][:door_ids], operator: current_tenant)
    end

    if room.update(room_params)
      render json: room_json(room)
    else
      render_error(room.errors.full_messages.join(', '))
    end
  end

  def destroy
    # "Delete" = soft archive so existing reservations / invoices that
    # reference the room keep working. Use unarchive to bring back.
    room = Room.find(params[:id])
    room.update!(archived: true)
    render json: { success: true }
  end

  def unarchive
    room = Room.find(params[:id])
    room.update!(archived: false)
    render json: room_json(room)
  end

  private

  def room_params
    params.require(:room).permit(
      :name, :capacity, :hourly_rate_in_cents,
      :visible, :rentable, :description,
      :square_footage, :allow_shorter_reservation_duration, :credit_cost,
      :photo,
      features: [],
    )
  end

  def room_json(room)
    {
      id: room.id,
      name: room.name,
      capacity: room.capacity,
      hourly_rate: room.hourly_rate_in_cents,
      description: room.description,
      visible: room.visible,
      rentable: room.rentable,
      square_footage: room.square_footage,
      allow_shorter_reservation_duration: room.allow_shorter_reservation_duration,
      credit_cost: room.credit_cost,
      features: room.features || [],
      # This room's attached locks (ADR 0021) — full list, for the config UI.
      door_ids: room.doors.pluck(:id),
      archived: room.archived,
      photo_url: (room.photo.attached? ? url_for(room.photo) : nil rescue nil),
    }
  end
end
