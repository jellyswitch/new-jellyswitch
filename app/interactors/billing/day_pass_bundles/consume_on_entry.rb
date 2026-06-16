class Billing::DayPassBundles::ConsumeOnEntry
  include Interactor

  delegate :user, :location, to: :context

  def call
    tz    = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date

    # Guard 1: active subscription
    return if user.has_active_subscription?

    # Guard 2: active lease at this location
    return if user.has_active_lease?(location)

    # Guard 3: reservation today at this location
    day_start = today.in_time_zone(tz).beginning_of_day
    day_end   = today.in_time_zone(tz).end_of_day
    return if user.reservations
                  .where(cancelled: false)
                  .where(datetime_in: day_start..day_end)
                  .exists?

    # Guard 4: a non-bundle DayPass already covers today (e.g. individually purchased)
    return if user.day_passes.for_location(location).for_day(today).exists?

    # Find the active bundle for this location
    bundle = user.day_pass_bundles.active.where(location: location).first
    return unless bundle

    # Mint + burn INSIDE the row lock, idempotent on the business-day window
    window_start, window_end = location.business_day_window
    bundle.with_lock do
      already = bundle.redemptions
                      .where(kind: "entry")
                      .where(redeemed_at: window_start...window_end)
                      .exists?
      next if already

      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           today
      )
      bundle.burn_locked!(kind: :entry, performed_by: user, day_pass: day_pass)
    end
  rescue DayPassBundle::NoPassesRemaining
    # emptied between gate and burn — door already authorized; admin can restore
  end
end
