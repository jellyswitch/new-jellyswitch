class Billing::Reservations::RedeemBundlePass
  include Interactor

  # Reserve-time bundle redemption (ADR 0015, auto since ADR 0029). Spend one
  # prepaid day-pass-bundle pass to cover a $0 (call) room: mint a DayPass for
  # the reservation's date (the same artifact ConsumeOnEntry mints on door
  # entry) and burn one pass. The minted DayPass is what makes ChargeCalculator
  # return 0 (so ChargeAtBooking no-ops) and grants access — pricing/permissions
  # recognize bundles only via a DayPass.
  #
  # Two triggers: the client's explicit use_bundle_pass decision, or — for
  # member self-serve bookings of an INCLUDED room (ADR 0029, Pratik/Cowork
  # Tahoe 2026-08-26) — automatically: holding a bundle IS the intent to spend
  # a pass on the dates you book, so a client that never sends the flag (older
  # app build, any web path) must not dead-end in EnforceCoverage's 422.
  #
  # Runs after SaveRoomReservation (validated, persisted reservation) and before
  # ChargeAtBooking (so the minted pass zeroes the charge). Paid rooms are never
  # covered, and members/leaseholders are already covered (mirrors ConsumeOnEntry
  # guards 1-2) so they never spend a pass.
  #
  # ONE pass per booker per business-day period, reconciled with the door: the
  # burn dedupe keys on the redemption ledger within the reservation's
  # business-day window (Location#business_day_window, 4am rollover), counting
  # both door "entry" and reserve "reservation" burns. The reserve burn stamps
  # redeemed_at at the reservation's start so the door sees it on the booking's
  # business day — including future-dated bookings and bookings that straddle the
  # rollover. The checks run again inside the bundle row lock to close the
  # door/reserve race. No demo gate needed — a prepaid pass is state-agnostic;
  # the pricing path (gated in ChargeAtBooking) moves no money in demo.

  delegate :reservation, :user, :use_bundle_pass, to: :context

  def call
    return unless reservation&.persisted?

    room = reservation.room
    return if room.hourly_rate_in_cents.to_i > 0 # paid rooms aren't covered by passes
    return unless use_bundle_pass || auto_redeem?(room)

    location = room.location
    return if user.has_active_subscription?     # already covered — never spend a pass
    return if user.has_active_lease?(location)

    day = reservation.datetime_in.to_date
    window_start, window_end = location.business_day_window(reservation.datetime_in)

    return if covered_for_day?(location, day)
    return if burned_in_window?(location, window_start, window_end)

    # usable_on (ADR 0018): a pass may not cover a date past its bundle's
    # expiration — a future-dated booking must draw a bundle that survives the
    # reservation's day, exactly like ScheduleDay (an expiring pack can't be
    # emptied onto far-future bookings). draw_order: the canonical
    # soonest-expiring-first pick, matching the CoverageState preview so the
    # bundle it showed is the bundle that burns.
    tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    bundle = user.day_pass_bundles.usable_on(day, tz).where(location: location).draw_order.first
    return unless bundle # no bundle usable for that date → fall through to normal pricing

    # Day Office outcome, computed in the lock and announced after it —
    # notifications are never enqueued from inside a transaction (ADR 0026).
    office_pass = nil
    office_hold = nil

    bundle.with_lock do
      # Re-check under the lock to close the concurrent door/reserve race.
      next if covered_for_day?(location, day)
      next if burned_in_window?(location, window_start, window_end)

      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           day,
        imported:      true,
        reservation:   reservation,
      )
      bundle.burn_locked!(kind: "reservation", performed_by: user, day_pass: day_pass,
                          reservation: reservation, redeemed_at: reservation.datetime_in)

      # A Day Office bundle spent on room coverage still spends an OFFICE day,
      # so take the office too (ADR 0026) — inside the bundle lock, matching
      # the lock order everywhere else (bundle row → pool join rows).
      #
      # Two DIFFERENT reservations end up attached to this one pass and must
      # not be confused (ADR 0019): `day_pass.reservation` is the member's own
      # covered booking, set above and never touched here; the office hold is
      # linked only through reservations.day_office_pass_id, which
      # Allocator.allocate! sets on the row it creates.
      #
      # Best-effort: a full pool leaves the booking covered and office-less
      # rather than failing a reservation the member already has.
      if bundle.day_pass_type.day_office?
        office_pass = day_pass
        office_hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
      end

      context.redeemed_bundle = bundle
      context.bundle_redemption_day_pass = day_pass
      context.office_hold = office_hold
      context.outcome = :redeemed
    end

    # Narrow known wart: if a LATER organizer step fails, #rollback destroys
    # the pass (releasing the hold with it) after this has already gone out.
    # Accepted — the alternative is delaying the member's office confirmation
    # past the booking flow for a rollback that effectively never fires here
    # (the minted pass is what zeroes the charge, so ChargeAtBooking no-ops).
    if office_pass
      if office_hold
        DayOffices::Notify.assigned(day_pass: office_pass)
      else
        # booked_, not walk_in_: this burn can be weeks ahead of the date, so
        # both the member push and the staff alert carry the booking's date and
        # never claim anyone has arrived.
        DayOffices::Notify.booked_no_office(day_pass: office_pass)
      end
    end
  rescue DayPassBundle::NoPassesRemaining
    Rails.logger.info("RedeemBundlePass: bundle emptied for reservation #{reservation&.id}; falling through to pricing")
  end

  # If a later organizer step fails, undo the burn so a never-committed booking
  # doesn't silently spend a pass. Capped refund (refund_pass_locked!) — never
  # over the pack size.
  def rollback
    bundle = context.redeemed_bundle
    day_pass = context.bundle_redemption_day_pass
    return unless bundle && day_pass

    bundle.with_lock do
      bundle.redemptions.where(day_pass_id: day_pass.id, kind: "reservation").destroy_all
      day_pass.destroy
      bundle.refund_pass_locked!
    end
  rescue => e
    Rails.logger.error("RedeemBundlePass rollback failed for reservation #{reservation&.id}: #{e.class}: #{e.message}")
    Honeybadger.notify(e) rescue nil
  end

  private

  # Auto-burn (ADR 0029): scoped to member self-serve via enforce_coverage —
  # the same opt-in the 422 guard uses, so exactly the flows that would BLOCK
  # an uncovered booking now cover it themselves instead; admin/on-behalf
  # flows (which don't set it) keep explicit control via schedule_bundle_days.
  # Scoped to included rooms so a free NON-included room never silently spends
  # a pass. Every other guard still applies: already covered, burned in the
  # business-day window, subscriber/leaseholder, and no-bundle all fall
  # through without burning.
  def auto_redeem?(room)
    context.enforce_coverage && room.include_with_day_pass?
  end

  # A purchased day pass or a prior bundle mint already covers that calendar day.
  def covered_for_day?(location, day)
    user.day_passes.for_location(location).for_day(day).exists?
  end

  # The booker already burned a pass (door entry OR another reservation) in the
  # reservation's business-day window — even across the 4am rollover where the
  # calendar dates of the two minted passes would differ.
  def burned_in_window?(location, window_start, window_end)
    DayPassBundleRedemption
      .where(day_pass_bundle: user.day_pass_bundles.where(location: location))
      .where(kind: %w[entry reservation], redeemed_at: window_start...window_end)
      .exists?
  end
end
