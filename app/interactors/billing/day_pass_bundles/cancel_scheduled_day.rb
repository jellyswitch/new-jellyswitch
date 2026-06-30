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
      # I1: delegate restore+log to the shared restore_locked! helper.
      # guest_name stores the cancelled date in ISO form (no dedicated column).
      bundle.restore_locked!(by: context.performed_by, reason: day_pass.day.iso8601, kind: "schedule_cancel")
      redemption.update!(day_pass: nil) # detach before destroying the pass
      day_pass.destroy!
    end

    context.bundle  = bundle
    context.outcome = :cancelled
  end
end
