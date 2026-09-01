class Billing::DayPassBundles::ConsumeOnEntry
  include Interactor

  delegate :user, :location, to: :context

  def call
    tz    = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date

    # Guard 1: active subscription
    if user.has_active_subscription?
      context.outcome = :already_covered
      return
    end

    # Guard 2: active lease at this location
    if user.has_active_lease?(location)
      context.outcome = :already_covered
      return
    end

    # Guard 3: reservation today at this location. Scoped to the booked
    # room's building — a reservation at ANOTHER building doesn't cover
    # entry here, so it must not suppress the bundle burn. Nil location
    # keeps the unscoped legacy behavior.
    day_start = today.in_time_zone(tz).beginning_of_day
    day_end   = today.in_time_zone(tz).end_of_day
    reservations_today = user.reservations
                             .where(cancelled: false)
                             .where(datetime_in: day_start..day_end)
    reservations_today = reservations_today.joins(:room).where(rooms: { location_id: location.id }) if location
    if reservations_today.exists?
      context.outcome = :already_covered
      return
    end

    # Guard 4: a non-bundle DayPass already covers today (e.g. individually purchased)
    if user.day_passes.for_location(location).for_day(today).exists?
      context.outcome = :already_covered
      return
    end

    # Find the active bundle for this location. draw_order: the canonical
    # soonest-expiring-first pick (ADR 0018) — a member holding an expiring
    # pack plus a perpetual one must spend the expiring pack at the door,
    # matching every other spender.
    bundle = user.day_pass_bundles.active.where(location: location).draw_order.first
    unless bundle
      context.outcome = :no_bundle
      return
    end

    # Mint + burn INSIDE the row lock, idempotent on the business-day window.
    # Count BOTH door "entry" and reserve-time "reservation" burns (ADR 0015):
    # a pass redeemed at booking stamps redeemed_at at the reservation's start,
    # so a same-business-day reservation (incl. one straddling the 4am rollover,
    # where Guards 3/4 key on the calendar date and can miss it) is seen here and
    # the door does not burn a second pass.
    window_start, window_end = location.business_day_window

    # Computed inside the lock, acted on after it. Notifications must never be
    # enqueued from inside a transaction (ADR 0026) — the door has already
    # opened by the time we get here and nothing about telling the member is
    # worth holding the bundle row for.
    office_pass = nil
    office_hold = nil

    bundle.with_lock do
      already = bundle.redemptions
                      .where(kind: %w[entry reservation])
                      .where(redeemed_at: window_start...window_end)
                      .exists?
      if already
        context.outcome = :already_covered
        next
      end

      # `imported: true` skips DayPass member-lifecycle side effects
      # (welcome-drip enrollment + activity-feed "bought a day pass" entry).
      # This minted pass is an internal accounting artifact of burning a
      # prepaid bundle, not a fresh day-pass purchase — the burn is already
      # recorded as a DayPassBundleRedemption. Firing those side effects on
      # every building entry would mis-log the event and re-enroll the member
      # daily. NOT marked `complimentary` — the pass is prepaid, not comped,
      # and must still count toward `DayPass.purchased` (door-access check).
      # Bundle revenue is recognized once at purchase; these entry passes are
      # excluded from day-pass revenue via the `not_bundle_sourced` scope.
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           today,
        imported:      true
      )
      bundle.burn_locked!(kind: :entry, performed_by: user, day_pass: day_pass)

      # Day Office walk-in (ADR 0026, decision #4). The member tapped a door
      # without scheduling, so nobody has reserved them a room yet — take one
      # now, INSIDE the bundle lock (lock order: bundle row → pool join rows).
      # Best-effort by design: a full pool must NOT undo the burn or refuse
      # entry. The pass is spent, the door opens, the member is told their
      # access still works, and staff are paged to reassign or restore. Any
      # other outcome would leave someone standing at a door they are entitled
      # to walk through.
      if bundle.day_pass_type.day_office?
        office_pass = day_pass
        office_hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
      end

      context.day_pass    = day_pass
      context.office_hold = office_hold
      context.outcome     = :redeemed
    end

    # Outcome is :redeemed either way — the office is a bonus on top of access,
    # never a precondition for it.
    if context.outcome == :redeemed && office_pass
      if office_hold
        DayOffices::Notify.assigned(day_pass: office_pass)
      else
        DayOffices::Notify.walk_in_no_office(day_pass: office_pass)
      end
    end
  rescue DayPassBundle::NoPassesRemaining
    # emptied between gate and burn — door already authorized; admin can restore
  end
end
