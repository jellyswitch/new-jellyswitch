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
    # working_day_start/end may be stored as strings like "06:00" or integers
    parse_hour = ->(val, default) {
      return default if val.nil?
      val.is_a?(String) ? val.split(':').first.to_i : val.to_i
    }
    start_hour = parse_hour.call(location&.working_day_start, 8)
    end_hour = parse_hour.call(location&.working_day_end, 18)

    zone = location&.time_zone || 'UTC'
    slots = []
    current_time = date.in_time_zone(zone).change(hour: start_hour)
    end_time = date.in_time_zone(zone).change(hour: end_hour)

    # If this is today, skip past slots. Round up to the next 15-min mark
    # so the user can't pick a start time that's already gone by.
    now_in_zone = Time.current.in_time_zone(zone)
    if date == now_in_zone.to_date
      floor = now_in_zone.change(min: (now_in_zone.min / 15).floor * 15, sec: 0)
      min_start = floor + 15.minutes
      current_time = min_start if current_time < min_start
    end

    while current_time < end_time
      available = room.available?(start_time: current_time, duration: 15)
      slots << {
        time: current_time.strftime("%H:%M"),
        hour: current_time.hour,
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

    sub_info = user.subscription_reservation_charge_info(location, minutes, room: room)
    dp_info = user.day_pass_reservation_charge_info(location, date, minutes, room: room)

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

    # Coverage check: if the user has no active subscription, no day pass
    # for this date, and no active lease, they need a day pass to book.
    needs_cov = !user.has_active_subscription? &&
                !user.has_active_day_pass_at_location?(location, date) &&
                !user.has_active_lease?(location) &&
                !user.admin_or_manager?(location) &&
                !user.superadmin?

    if needs_cov
      suggested = pick_default_room_booking_day_pass_type(location)
      if suggested
        base[:needs_day_pass] = true
        base[:day_pass] = {
          type_id: suggested.id,
          name: suggested.name,
          amount_in_cents: suggested.amount_in_cents,
          included_meeting_room_minutes: suggested.included_meeting_room_minutes,
          overage_rate_in_cents: suggested.overage_rate_in_cents,
          date: date.to_s,
        }

        # Project the same overage logic as if this day pass were already
        # purchased, so the summary can warn about overages up front.
        # Priced rooms never count against day pass allowance.
        if room.hourly_rate_in_cents.to_i == 0
          included = suggested.included_meeting_room_minutes
          if included.present? && minutes > included
            over_min = minutes - included
            over_min_rounded = (over_min / 15.0).ceil * 15
            over_rate_per_min = (suggested.overage_rate_in_cents || 0) / 60.0
            over_cents = (over_rate_per_min * over_min_rounded).to_i
            base[:charge_type] = 'partial_overage'
            base[:estimated_cost] = over_cents
            base[:plan_minutes_remaining] = included
            base[:plan_minutes_total] = included
            base[:overage_rate] = suggested.overage_rate_in_cents
            base[:source] = 'projected_day_pass'
            base[:included_in_plan] = false
          elsif included.present?
            base[:charge_type] = 'free'
            base[:estimated_cost] = 0
            base[:plan_minutes_remaining] = included - minutes
            base[:plan_minutes_total] = included
            base[:source] = 'projected_day_pass'
            base[:included_in_plan] = true
          end
        end
      else
        base[:needs_day_pass] = true
        base[:day_pass] = nil
      end
    else
      base[:needs_day_pass] = false
    end

    render json: base
  end

  def reserve_now
    location = current_location
    return render json: { rooms: [] } unless location

    user = current_api_user
    zone = ActiveSupport::TimeZone[location.time_zone] || Time.zone
    now = Time.current.in_time_zone(zone)

    # Round up to next 15-min mark
    remainder = now.min % 15
    start_time = remainder == 0 ? now : now + (15 - remainder).minutes
    start_time = start_time.change(sec: 0)

    duration = user.preferred_meeting_duration.to_i
    duration = 60 if duration <= 0

    # Find available rooms
    end_time = start_time + duration.minutes
    booked_room_ids = Reservation.where(room: location.rooms.visible)
      .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
      .where(cancelled: false)
      .pluck(:room_id).uniq

    available_rooms = location.rooms.visible.where.not(id: booked_room_ids)
    available_rooms = available_rooms.rentable unless user.can_see_all_rooms?(location, start_time.to_date) rescue available_rooms

    available_list = available_rooms.to_a

    if available_list.empty?
      # No rooms — return unavailable list with free times
      all_rooms = location.rooms.visible.map do |room|
        current_booking = room.reservations.where(cancelled: false)
          .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?", Time.current, Time.current)
          .first
        overlap = room.reservations.where(cancelled: false)
          .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
          .order(:datetime_in).first unless current_booking
        free_at = current_booking&.datetime_out || overlap&.datetime_out
        {
          id: room.id, name: room.name, capacity: room.capacity,
          hourly_rate: room.hourly_rate_in_cents,
          amenities: room.amenities.pluck(:name),
          available: false,
          available_at: free_at&.in_time_zone(zone)&.strftime("%l:%M %p")&.strip,
        }
      end.sort_by { |r| r[:available_at] || '' }

      return render json: {
        rooms: all_rooms,
        no_rooms_available: true,
        start_time: start_time.iso8601,
        preferred_duration: duration,
      }
    end

    # Pick the hero room — preferred, then cheapest, then first
    preferred = available_list.find { |r| r.id == user.preferred_room_id }
    hero = preferred || available_list.min_by { |r| r.hourly_rate_in_cents.to_i } || available_list.first

    max_duration = [(hero.calculate_max_continuous_duration(start_time: start_time) rescue 240), 240].min

    # Pricing for hero room
    sub_info = user.subscription_reservation_charge_info(location, duration) rescue nil
    dp_info = user.day_pass_reservation_charge_info(location, start_time.to_date, duration) rescue nil

    should_charge = user.should_charge_for_reservation?(location, start_time.to_date) rescue true
    hourly = hero.hourly_rate_in_cents / 100.0
    total_price = hourly * (duration / 60.0)
    included = !should_charge && hero.hourly_rate_in_cents > 0

    if sub_info && sub_info[:charge_type] == :partial_overage
      included = false
      total_price = sub_info[:overage_amount_in_cents] / 100.0
    end
    if dp_info && dp_info[:charge_type] == :partial_overage
      included = false
      total_price = dp_info[:overage_amount_in_cents] / 100.0
    end

    included_minutes_remaining = sub_info&.dig(:remaining_free) || dp_info&.dig(:remaining_free)
    overage_rate_per_hour_cents = sub_info&.dig(:overage_rate_in_cents) || dp_info&.dig(:overage_rate_in_cents)
    has_plan = sub_info.present? || dp_info.present?

    room_json = ->(r, is_available, available_at = nil) {
      {
        id: r.id, name: r.name, capacity: r.capacity,
        description: r.description,
        hourly_rate: r.hourly_rate_in_cents,
        amenities: r.amenities.pluck(:name),
        available: is_available,
        available_at: available_at,
        preferred: r.id == user.preferred_room_id,
        photo_url: (r.photo.attached? ? url_for(r.photo) : nil rescue nil),
      }
    }

    other_available = available_list.reject { |r| r.id == hero.id }.sort_by { |r| r.hourly_rate_in_cents.to_i }
    unavailable_ids = location.rooms.visible.where.not(id: available_list.map(&:id)).pluck(:id)
    unavailable = location.rooms.visible.where(id: unavailable_ids).map do |r|
      current_booking = r.reservations.where(cancelled: false)
        .where("datetime_in <= ? AND (datetime_in + minutes * interval '1 minute') > ?", Time.current, Time.current)
        .first
      overlap = r.reservations.where(cancelled: false)
        .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
        .order(:datetime_in).first unless current_booking
      free_at = current_booking&.datetime_out || overlap&.datetime_out
      room_json.call(r, false, free_at&.in_time_zone(zone)&.strftime("%l:%M %p")&.strip)
    end

    render json: {
      hero_room: room_json.call(hero, true),
      available_rooms: other_available.map { |r| room_json.call(r, true) },
      unavailable_rooms: unavailable,
      start_time: start_time.iso8601,
      start_time_label: start_time.strftime("%-l:%M %p"),
      preferred_duration: duration,
      max_duration: max_duration,
      total_price: total_price,
      included_in_plan: included,
      included_minutes_remaining: included_minutes_remaining,
      should_charge: should_charge || (sub_info&.dig(:charge_type) == :partial_overage) || (dp_info&.dig(:charge_type) == :partial_overage),
      # Client uses these to compute effective price per room × current slider duration:
      pricing_context: {
        has_plan: has_plan,
        minutes_remaining: included_minutes_remaining.to_i,
        overage_rate_per_hour_cents: overage_rate_per_hour_cents.to_i,
        plan_label: sub_info ? 'plan' : (dp_info ? 'day pass' : nil),
      },
    }
  end

  private

  # Prefer the day pass type explicitly marked as the default for room
  # bookings. Fall back to cheapest non-free, non-Day-Office type.
  def pick_default_room_booking_day_pass_type(location)
    scope = DayPassType
      .where(operator_id: location.operator_id)
      .where("location_id = ? OR location_id IS NULL", location.id)
      .available
      .where(visible: true)
      .where("amount_in_cents > 0")
      .where.not("name ILIKE ?", "%office%")

    scope.where(default_for_room_booking: true).first ||
      scope.order(:amount_in_cents).first
  end

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
      photo_url: (room.photo.attached? ? url_for(room.photo) : nil rescue nil),
    }
  end
end
