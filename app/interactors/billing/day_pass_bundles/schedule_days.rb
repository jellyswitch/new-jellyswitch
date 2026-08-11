class Billing::DayPassBundles::ScheduleDays
  include Interactor

  def call
    # m2: pass each raw value straight to ScheduleDay — it owns date parsing and
    # validation. Pre-parsing here would raise before the transaction can roll back.
    dates = Array(context.dates)
    day_passes = []
    # Day Office passes ScheduleDay WOULD have announced (ADR 0026). Collected
    # here and fired after the transaction closes — see the comment below.
    to_notify = []

    ActiveRecord::Base.transaction do
      dates.each do |date|
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by,
          enforce_daily_limit: context.enforce_daily_limit,
          defer_notifications: true)

        if result.outcome != :scheduled
          context.outcome       = result.outcome
          context.day_pass_type = result.day_pass_type # set on :sold_out, nil otherwise
          # Coerce to Date so callers can safely call .strftime on failed_date.
          # For :invalid_date the raw value is a fine fallback (strftime isn't called).
          context.failed_date = (Date.parse(date.to_s) rescue date)
          raise ActiveRecord::Rollback
        end
        day_passes << result.day_pass
        to_notify << result.notify_day_pass if result.notify_day_pass
      end

      context.day_passes = day_passes
      context.outcome    = :scheduled
    end

    # Post-COMMIT, deliberately outside the block above. A notification
    # enqueued mid-transaction races the commit: Sidekiq can dequeue before the
    # rows are visible (the job discards on DeserializationError and the mailer
    # nil-bails, so the member silently never hears), and a later date failing
    # rolls the whole batch back under an already-sent confirmation. Bailing on
    # any non-:scheduled outcome is what makes the rollback case announce
    # nothing at all — there is no committed office to announce.
    return unless context.outcome == :scheduled

    to_notify.each { |day_pass| DayOffices::Notify.assigned(day_pass: day_pass) }
  end
end
