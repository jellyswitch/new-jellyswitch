class Billing::DayPassBundles::CancelScheduledDay
  include Interactor

  def call
    day_pass   = context.day_pass
    redemption = DayPassBundleRedemption.find_by(day_pass_id: day_pass.id, kind: "entry")
    bundle     = redemption&.day_pass_bundle

    unless bundle
      context.outcome = :not_scheduled
      return
    end

    tz    = ActiveSupport::TimeZone[day_pass.location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    if day_pass.day <= today
      context.outcome = :too_late
      return
    end

    bundle.with_lock do
      if bundle.passes_remaining.to_i < bundle.quantity_purchased.to_i
        bundle.update!(passes_remaining: bundle.passes_remaining + 1)
      end
      bundle.redemptions.create!(
        operator: bundle.operator, kind: "schedule_cancel",
        performed_by: context.performed_by, guest_name: day_pass.day.iso8601, redeemed_at: Time.current)
      redemption.update!(day_pass: nil) # detach before destroying the pass
      day_pass.destroy!
    end

    context.bundle  = bundle
    context.outcome = :cancelled
  end
end
