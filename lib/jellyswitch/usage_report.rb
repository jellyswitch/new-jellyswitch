
class Jellyswitch::UsageReport
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def reservations
    @reservations ||= user.reservations.this_month.group_by_day(:datetime_in).count.reject do |k,v|
      v < 1
    end
  end

  def door_punches
    # Room Entries are not building entries (ADR 0021) — a Room Lock open
    # doesn't count as a visit day here (the reservation already does).
    @door_punches ||= user.door_punches.where(room_entry: false).this_month.group_by_day(:created_at).count.reject do |k,v|
      v < 1
    end
  end

  def checkins
    @checkins ||= user.checkins.this_month.group_by_day(:datetime_in).count.reject do |k,v|
      v < 1
    end
  end

  def day_passes
    # `day` is a plain date — without time_zone: false groupdate treats it as
    # midnight UTC and shifts every pass back a day for Pacific tenants.
    @day_passes ||= user.day_passes.this_month.group_by_day(:day, time_zone: false).count.reject do |k,v|
      v < 1
    end
  end

  def days_used
    @days_used ||= reservations.merge(door_punches) do |_,o,n|
      o+n
    end.merge(checkins) do |_,o,n|
      o+n
    end.merge(day_passes) do |_,o,n|
      o+n
    end
  end

  def days_used_count
    days_used.count
  end

  def data_for_heatmap
    Hash[ days_used.map { |k, v| [k.to_time.to_i.to_s, v] } ]
  end
end
