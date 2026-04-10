class Api::V1::Admin::RoomsController < Api::V1::Admin::BaseController
  def index
    rooms = Room.where(operator: current_tenant).order(:name)

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

    if room.update(room_params)
      render json: room_json(room)
    else
      render_error(room.errors.full_messages.join(', '))
    end
  end

  def destroy
    room = Room.find(params[:id])
    room.destroy
    render json: { success: true }
  end

  private

  def room_params
    params.require(:room).permit(:name, :capacity, :hourly_rate_in_cents, :visible, :rentable, :description)
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
    }
  end
end
