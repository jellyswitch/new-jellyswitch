class Billing::DayPassBundles::ScheduleDays
  include Interactor

  def call
    dates = Array(context.dates).map { |d| d.is_a?(String) ? Date.parse(d) : d }
    day_passes = []

    ActiveRecord::Base.transaction do
      dates.each do |date|
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: context.user, location: context.location, date: date, performed_by: context.performed_by)

        if result.outcome != :scheduled
          context.outcome     = result.outcome
          context.failed_date = date
          raise ActiveRecord::Rollback
        end
        day_passes << result.day_pass
      end

      context.day_passes = day_passes
      context.outcome    = :scheduled
    end
  end
end
