class Api::V1::RoomsController < Api::V1::BaseController
  def index
    location = current_location
    return render json: [] unless location

    rooms = location.rooms.visible.order(:name)

    render json: rooms.map { |r| room_json(r) }
  end

  def availability
    room = Room.find(params[:id])
    date = Date.parse(params[:date]) rescue Date.current

    # Get all reservations for this room on this date
    reservations = room.reservations.where(cancelled: false)
      .where("datetime_in::date = ?", date)
      .order(:datetime_in)

    render json: {
      room: room_json(room),
      date: date.to_s,
      reservations: reservations.map { |r| {
        start: r.datetime_in.strftime("%H:%M"),
        end: r.datetime_out.strftime("%H:%M"),
        user: r.user.name,
      }},
    }
  end

  def time_slots
    room = Room.find(params[:id])
    date = Date.parse(params[:date]) rescue Date.current
    location = current_location

    # Generate 15-min slots from open to close
    start_hour = location&.working_day_start || 8
    end_hour = location&.working_day_end || 18

    slots = []
    current_time = date.in_time_zone(location&.time_zone || 'UTC').change(hour: start_hour)
    end_time = date.in_time_zone(location&.time_zone || 'UTC').change(hour: end_hour)

    while current_time < end_time
      available = room.available?(start_time: current_time, duration: 15)
      slots << {
        time: current_time.strftime("%H:%M"),
        label: current_time.strftime("%l:%M %p").strip,
        available: available,
      }
      current_time += 15.minutes
    end

    render json: { room: room_json(room), date: date.to_s, slots: slots }
  end

  def reserve_now
    location = current_location
    return render json: { rooms: [] } unless location

    user = current_api_user
    rooms = location.rooms.visible.order(:name)
    preferred_room_id = user.preferred_room_id
    preferred_duration = user.preferred_meeting_duration || 60

    room_data = rooms.map do |room|
      available = room.available_now? rescue false
      next_available = nil
      unless available
        # Find when room is next free
        next_res = room.reservations.where(cancelled: false)
          .where("datetime_out > ?", Time.current)
          .order(:datetime_out).first
        next_available = next_res&.datetime_out&.strftime("%l:%M %p")&.strip
      end

      {
        id: room.id,
        name: room.name,
        capacity: room.capacity,
        av: room.av,
        whiteboard: room.whiteboard,
        hourly_rate: room.hourly_rate_in_cents,
        available: available,
        available_at: next_available,
        preferred: room.id == preferred_room_id,
      }
    end

    # Sort: preferred first, then available, then by name
    room_data.sort_by! { |r| [r[:preferred] ? 0 : 1, r[:available] ? 0 : 1, r[:name]] }

    render json: { rooms: room_data, preferred_duration: preferred_duration }
  end

  private

  def room_json(room)
    {
      id: room.id,
      name: room.name,
      capacity: room.capacity,
      av: room.av,
      whiteboard: room.whiteboard,
      hourly_rate: room.hourly_rate_in_cents,
      rentable: room.rentable?,
      available: (room.available_now? rescue false),
    }
  end
end
