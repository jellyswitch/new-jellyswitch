module Api::V1::DoorUnlocking
  extend ActiveSupport::Concern

  private

  def user_can_access_building?(user, location)
    return false if user.nil?
    return true if user.superadmin?
    return true if location && user.admin_or_manager?(location)

    zone  = location&.time_zone.presence || "UTC"
    today = Time.current.in_time_zone(zone).to_date

    return true if user.has_active_subscription?
    return true if user.day_passes.where(day: today).any?
    return true if location && user.has_active_day_pass_bundle?(location)
    return true if location && user.has_active_lease?(location)

    # A reservation grants access only inside its ±window (ADR 0013), not all
    # day. Coarse-filter candidates by datetime_in (±(1 day + window) catches
    # midnight spillover and any reasonable duration), then make the exact in/out
    # call in Ruby. window_minutes is passed through so access_window_open? needn't
    # reload the operator per row.
    window_minutes = location&.operator&.building_access_window_minutes || 60
    now = Time.current
    window = window_minutes.minutes
    user.reservations
        .where(cancelled: false)
        .where(datetime_in: (now - 1.day - window)..(now + 1.day + window))
        .any? { |reservation| reservation.access_window_open?(now, window_minutes: window_minutes) }
  end

  ROOM_LOCK_EARLY_GRACE = 10.minutes

  # ADR 0021: a Room Lock opens for staff anytime, or the reservation
  # holder during their booking — including up to ROOM_LOCK_EARLY_GRACE
  # early, but only when no other booking still occupies the room (early
  # building entry is hospitality; early ROOM entry collides with the
  # previous meeting).
  def user_can_open_room_lock?(user, door)
    return false if user.nil? || door.room.nil?
    return true if user.superadmin?

    location = door.location
    return true if location && user.admin_or_manager?(location)

    # Reservation's default_scope already excludes cancelled bookings.
    now = Time.current
    holder_res = door.room.reservations
      .where(user: user)
      .overlapping(now, now + ROOM_LOCK_EARLY_GRACE)
      .order(:datetime_in)
      .first
    return false unless holder_res

    # Booking hasn't started yet (we're inside the grace window): the room
    # must actually be free — a still-running prior booking wins.
    if holder_res.datetime_in > now
      occupied = door.room.reservations
        .where.not(id: holder_res.id)
        .overlapping(now, now)
        .exists?
      return !occupied
    end

    true
  end

  def call_kisi_unlock(door, _location = nil)
    # Routed through Kisi::Client so the manual /doors/:id/unlock path
    # benefits from the same persistent connection the async job uses.
    # `location` is ignored (Kisi::Client reads door.location internally).
    Kisi::Client.unlock(door)[:parsed]
  end

  def perform_unlock(door:, user:, location:, method:)
    room_entry = door.room_lock?
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, room_entry: room_entry)
    # Bundle burn-on-entry is a BUILDING-entry semantic — a Room Entry
    # never spends a pass (ADR 0021; the holder's reservation already
    # granted access anyway).
    unless room_entry
      begin
        Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      rescue => e
        Rails.logger.error("[DoorUnlocking] ConsumeOnEntry failed: #{e.class}: #{e.message}")
        Honeybadger.notify(e) rescue nil
      end
    end
    response = call_kisi_unlock(door, location)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, json: response, room_entry: room_entry)
    response
  end
end
