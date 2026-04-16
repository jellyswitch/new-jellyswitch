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

  def pricing
    room = Room.find(params[:id])
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    minutes = (params[:minutes] || 60).to_i

    user = current_api_user
    location = current_location

    # Credit info (if credits enabled)
    credit_info = nil
    if location.try(:credits_enabled?)
      credit_cost = room.try(:credit_cost) || 0
      credit_charge = credit_cost > 0 ? ((credit_cost / 60.0) * minutes).ceil : 0
      credit_info = {
        credits_enabled: true,
        credit_cost_per_hour: credit_cost,
        credit_charge: credit_charge,
        credit_balance: user.credit_balance,
        sufficient_credits: user.credit_balance >= credit_charge,
        credit_price_cents: location.try(:credit_cost_in_cents) || 0,
      }
    end

    sub_info = user.subscription_reservation_charge_info(location, minutes)
    dp_info = user.day_pass_reservation_charge_info(location, date, minutes)

    base = if sub_info
      {
        included_in_plan: sub_info[:charge_type] == :free,
        charge_type: sub_info[:charge_type].to_s,
        estimated_cost: sub_info[:overage_amount_in_cents] || 0,
        plan_minutes_remaining: sub_info[:remaining_free],
        plan_minutes_total: sub_info[:included_minutes],
        used_minutes: sub_info[:used_minutes],
        overage_rate: sub_info[:overage_rate_in_cents],
        source: 'subscription',
      }
    elsif dp_info
      {
        included_in_plan: dp_info[:charge_type] == :free,
        charge_type: dp_info[:charge_type].to_s,
        estimated_cost: dp_info[:overage_amount_in_cents] || 0,
        plan_minutes_remaining: dp_info[:remaining_free],
        plan_minutes_total: nil,
        overage_rate: dp_info[:overage_rate_in_cents],
        source: 'day_pass',
      }
    else
      hourly_rate = room.hourly_rate_in_cents || 0
      estimated = (hourly_rate * minutes / 60.0).round
      {
        included_in_plan: false,
        charge_type: hourly_rate > 0 ? 'full' : 'free',
        estimated_cost: estimated,
        plan_minutes_remaining: nil,
        plan_minutes_total: nil,
        overage_rate: nil,
        source: 'hourly',
      }
    end

    base[:credits] = credit_info if credit_info
    render json: base
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
        description: room.description,
        hourly_rate: room.hourly_rate_in_cents,
        amenities: room.amenities.pluck(:name),
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
      description: room.description,
      hourly_rate: room.hourly_rate_in_cents,
      amenities: room.amenities.pluck(:name),
      rentable: room.rentable?,
      available: (room.available_now? rescue false),
    }
  end
end
