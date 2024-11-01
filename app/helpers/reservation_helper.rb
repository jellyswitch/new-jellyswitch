module ReservationHelper
  def find_todays_reservations(location)
    location.rooms.map do |room|
      groups = room.reservations.for_day(Time.current).group_by(&:user)

      result = groups.keys.map do |key|
        minutes = groups[key].sum(&:minutes)
        hours = minutes.to_f / 60.0
        {
          user: key,
          minutes: minutes,
          hours: hours,
        }
      end.sort { |a, b| a[:minutes] <=> b[:minutes] }.reverse
      total_minutes = result.sum { |s| s[:minutes] }
      hours = total_minutes.to_f / 60.0
      {
        room: room,
        users: result,
        minutes: total_minutes,
        hours: hours,
      }
    end.sort { |a, b| a[:minutes] <=> b[:minutes] }.reverse
  end

  def calculate_available_time_slots(date, day_or_night)
    if day_or_night == "day"
      start_time = date.in_time_zone(Time.zone).beginning_of_day # Start at midnight
      end_time = date.in_time_zone(Time.zone).change(hour: 11, min: 45) # End at 11:45 AM
    elsif day_or_night == "night"
      start_time = date.in_time_zone(Time.zone).change(hour: 12) # Start at noon
      end_time = date.in_time_zone(Time.zone).end_of_day # End at the last minute of the day
    end

    now = Time.zone.now
    time_slots = []

    while start_time <= end_time
      time_slots << start_time if start_time > now
      start_time += 15.minutes
    end

    time_slots
  end

  def calculate_nearest_time_slot(date)
    now = Time.zone.now
    day_or_night = now.hour < 12 ? "day" : "night"

    available_time_slots = calculate_available_time_slots(date, day_or_night)

    available_time_slots.first
  end
end
