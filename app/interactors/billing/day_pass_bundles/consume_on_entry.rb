class Billing::DayPassBundles::ConsumeOnEntry
  include Interactor

  delegate :user, :location, to: :context

  def call
    zone  = location&.time_zone.presence || "UTC"
    today = Time.current.in_time_zone(zone).to_date

    # Guard 1: already has a DayPass for today at this location — re-entry is free
    return if user.day_passes.for_location(location).for_day(today).exists?

    # Guard 2: otherwise covered (active subscription, active lease, or reservation today)
    return if user.has_active_subscription?
    return if user.has_active_lease?(location)

    day_start = today.in_time_zone(zone).beginning_of_day
    day_end   = today.in_time_zone(zone).end_of_day
    has_reservation = user.reservations
                          .where(cancelled: false)
                          .where(datetime_in: day_start..day_end)
                          .exists?
    return if has_reservation

    # Guard 3: find an active bundle for this location
    bundle = user.day_pass_bundles.active.where(location: location).first
    return unless bundle

    # Mint the DayPass and burn a pass — atomic
    ActiveRecord::Base.transaction do
      day_pass = DayPass.create!(
        user:          user,
        billable:      user,
        operator:      bundle.operator,
        location:      location,
        day_pass_type: bundle.day_pass_type,
        day:           today
      )
      bundle.burn!(kind: :entry, performed_by: user, day_pass: day_pass)
    end
  rescue DayPassBundle::NoPassesRemaining
    # Race condition: another process beat us to the last pass — do nothing
  end
end
