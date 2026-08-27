module Api::V1::DoorUnlocking
  extend ActiveSupport::Concern

  private

  def user_can_access_building?(user, location)
    return false if user.nil?
    return true if user.superadmin?
    return true if location && user.admin_or_manager?(location)

    # Approval is the HARD GATE for building access (Nash incident follow-up,
    # 2026-08-08): screening happens BEFORE the door opens. An unapproved
    # account gets no keys and no unlock regardless of day passes, bundles,
    # memberships, leases, or reservations — the app holds them on the
    # Welcome/pending screen, and staff approve from the members queue.
    # Purchasing and booking stay self-serve (coverage-gated only).
    return false unless user.approved?

    zone  = location&.time_zone.presence || "UTC"
    today = Time.current.in_time_zone(zone).to_date

    # Membership access now honors the plan's building_access_level (none /
    # business_hours / all_hours) — the SAME check the Keys tab uses — instead
    # of granting any active subscriber a 24-7 unlock. This closes the gap where
    # a mailbox/community/free-tier member (level none) could open a door, and
    # enforces the business-hours window for that tier at unlock time.
    return true if user.has_building_access_membership?(location)

    # Day-pass and bundle access are bounded to the location's posted HOURS
    # (time-of-day only, not the open_<day> staffed-days flags — weekend
    # daytime day-pass entry is established behavior): a pass covers the DAY,
    # but the door only opens between working_day_start and working_day_end
    # (Nash, 2026-08-07 — a 1:34 AM pass purchase opened the lobby at
    # 1:38 AM; hours are 5 AM–8 PM). A pass TYPE flagged
    # always_allow_building_access keeps 24/7 access — the same escape hatch
    # the membership tiers get via all_hours. Membership, lease, staff, and
    # reservation-±window access (below) are unchanged.
    open_now = location.nil? || location.within_posted_hours?
    # A pass covers the LOCATION it was bought for — at a multi-location
    # operator a pass for one location must not open another location's
    # doors. for_location is the lenient HasLocation scope
    # (location_id = ? OR location_id IS NULL) so legacy location-less
    # passes keep working; a nil gate location (no location context) keeps
    # the unscoped behavior rather than locking members out.
    todays_passes = user.day_passes.where(day: today)
    todays_passes = todays_passes.for_location(location) if location
    if todays_passes.any?
      return true if open_now
      return true if todays_passes.joins(:day_pass_type)
                                  .where(day_pass_types: { always_allow_building_access: true }).exists?
    end
    if location && user.has_active_day_pass_bundle?(location)
      return true if open_now
      return true if user.day_pass_bundles.active.where(location: location)
                         .joins(:day_pass_type)
                         .where(day_pass_types: { always_allow_building_access: true }).exists?
    end
    return true if location && user.has_active_lease?(location)

    # A reservation grants access only inside its ±window (ADR 0013), not all
    # day. Coarse-filter candidates by datetime_in (±(1 day + window) catches
    # midnight spillover and any reasonable duration), then make the exact in/out
    # call in Ruby. window_minutes is passed through so access_window_open? needn't
    # reload the operator per row.
    window_minutes = location&.operator&.building_access_window_minutes || 60
    now = Time.current
    window = window_minutes.minutes
    reservations = user.reservations
                       .where(cancelled: false)
                       .where(datetime_in: (now - 1.day - window)..(now + 1.day + window))
    # A reservation admits its holder to the building the booked ROOM is in —
    # at a multi-location operator a booking in one building must not open the
    # others' doors during its window. Nil gate location keeps the unscoped
    # behavior (no location context), the same lenient convention as the
    # membership and day-pass clauses.
    reservations = reservations.joins(:room).where(rooms: { location_id: location.id }) if location
    reservations.any? { |reservation| reservation.access_window_open?(now, window_minutes: window_minutes) }
  end

  # ADR 0021 room-lock rule (staff anytime; holder during their booking,
  # incl. the early grace when the room is free). The logic lives on the
  # model — Door#openable_as_room_lock_by? — so the operator web and legacy
  # /api unlock paths share the exact same rule.
  def user_can_open_room_lock?(user, door)
    door.openable_as_room_lock_by?(user)
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
    # Routed through Kisi::Client so the manual /doors/:id/unlock path
    # benefits from the same persistent connection the async job uses.
    result = Kisi::Client.unlock(door)
    # Record what Kisi actually answered, mirroring KisiUnlockJob's
    # reconciliation: a Kisi-side refusal (controller offline, fac001) is a
    # "failed" punch. Before this, the row said "unlocked" with the error
    # buried in json — and the member was told the door opened.
    DoorPunch.create!(
      user: user, door: door, operator: current_tenant, method: method,
      json: result[:parsed] || result[:body],
      status: result[:success] ? "unlocked" : "failed",
      room_entry: room_entry,
    )
    result
  end
end
