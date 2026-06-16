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

    # Guard 3: reservation today at this location
    day_start = today.in_time_zone(tz).beginning_of_day
    day_end   = today.in_time_zone(tz).end_of_day
    if user.reservations
           .where(cancelled: false)
           .where(datetime_in: day_start..day_end)
           .exists?
      context.outcome = :already_covered
      return
    end

    # Guard 4: a non-bundle DayPass already covers today (e.g. individually purchased)
    if user.day_passes.for_location(location).for_day(today).exists?
      context.outcome = :already_covered
      return
    end

    # Find the active bundle for this location
    bundle = user.day_pass_bundles.active.where(location: location).first
    unless bundle
      context.outcome = :no_bundle
      return
    end

    # Mint + burn INSIDE the row lock, idempotent on the business-day window
    window_start, window_end = location.business_day_window
    bundle.with_lock do
      already = bundle.redemptions
                      .where(kind: "entry")
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
      context.outcome = :redeemed
    end
  rescue DayPassBundle::NoPassesRemaining
    # emptied between gate and burn — door already authorized; admin can restore
  end
end
