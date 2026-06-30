class Billing::DayPassBundles::ScheduleDay
  include Interactor

  HORIZON_DAYS = 90

  delegate :user, :location, :performed_by, to: :context

  def call
    tz    = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    date  = context.date.is_a?(String) ? Date.parse(context.date) : context.date

    if date < today || date > today + HORIZON_DAYS.days
      context.outcome = :invalid_date
      return
    end

    if already_covered?(date, tz)
      context.outcome = :already_covered
      return
    end

    bundle = eligible_bundle(date, tz)
    unless bundle
      context.outcome = :no_bundle
      return
    end

    bundle.with_lock do
      # `imported: true` skips DayPass member-lifecycle side effects — the burn
      # is the audit record (mirrors ConsumeOnEntry). NOT complimentary: the
      # pass is prepaid and must count toward door-access checks.
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           date,
        imported:      true,
      )
      bundle.burn_locked!(kind: :entry, performed_by: performed_by, day_pass: day_pass)
      context.bundle   = bundle
      context.day_pass = day_pass
      context.outcome  = :scheduled
    end
  rescue DayPassBundle::NoPassesRemaining
    context.outcome = :no_bundle
  end

  private

  # Mirrors ConsumeOnEntry's guards, scoped to the target date instead of today.
  def already_covered?(date, tz)
    return true if user.has_active_subscription?
    return true if user.has_active_lease?(location)

    day_start = date.in_time_zone(tz).beginning_of_day
    day_end   = date.in_time_zone(tz).end_of_day
    return true if user.reservations.where(cancelled: false)
                       .where(datetime_in: day_start..day_end).exists?

    user.day_passes.for_location(location).for_day(date).exists?
  end

  # Active, covers the location, not expired before the target date; soonest to
  # expire first (NULLs/perpetual last), then oldest.
  def eligible_bundle(date, tz)
    user.day_pass_bundles.active.where(location: location)
        .where("expires_at IS NULL OR expires_at > ?", date.in_time_zone(tz).end_of_day)
        .order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC"))
        .first
  end
end
