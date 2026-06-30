class Billing::DayPassBundles::ScheduleDays
  include Interactor

  def call
    # m2: pass each raw value straight to ScheduleDay — it owns date parsing and
    # validation. Pre-parsing here would raise before the transaction can roll back.
    dates = Array(context.dates)
    day_passes = []

    ActiveRecord::Base.transaction do
      dates.each do |date|
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by)

        if result.outcome != :scheduled
          context.outcome     = result.outcome
          # Coerce to Date so callers can safely call .strftime on failed_date.
          # For :invalid_date the raw value is a fine fallback (strftime isn't called).
          context.failed_date = (Date.parse(date.to_s) rescue date)
          raise ActiveRecord::Rollback
        end
        day_passes << result.day_pass
      end

      context.day_passes = day_passes
      context.outcome    = :scheduled
    end
  end
end
