module ReservationHelper
  def find_todays_reservations(operator)
    operator.locations.map do |location|
      location.rooms
    end.flatten.map do |room|
      groups = room.reservations.for_day(Time.current).group_by(&:user)

      result = groups.keys.map do |key|
        minutes = groups[key].sum(&:minutes)
        hours = minutes.to_f / 60.0
        {
          user: key,
          minutes: minutes,
          hours: hours
        }
      end.sort {|a, b| a[:minutes] <=> b[:minutes] }.reverse
      total_minutes = result.sum {|s| s[:minutes]}
      hours = total_minutes.to_f / 60.0
      {
        room: room,
        users: result,
        minutes: total_minutes,
        hours: hours
      }
    end.sort { |a, b| a[:minutes] <=> b[:minutes] }.reverse
  end

  def calculate_available_time_slots(date)
    start_time = date.in_time_zone(Time.zone).change(hour: 6)
    end_time = date.in_time_zone(Time.zone).change(hour: 20)
    now = Time.zone.now

    time_slots = []
    while start_time <= end_time
      time_slots << start_time if start_time > now
      start_time += 15.minutes
    end

    time_slots
  end
end
