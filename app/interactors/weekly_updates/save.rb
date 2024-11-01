class WeeklyUpdates::Save
  include Interactor
  delegate :week_start, :week_end, :operator, :location, to: :context

  def call
    weekly_report = Jellyswitch::WeeklyReport.new(operator, location, week_start, week_end)
    previous_weekly_report = Jellyswitch::WeeklyReport.new(operator, location, week_start - 1.week, week_end - 1.week)

    weekly_update = WeeklyUpdate.from_weekly_reports(weekly_report, previous_weekly_report)

    if weekly_update.save
      context.weekly_update = weekly_update
      context.notifiable = weekly_update
    else
      context.fail!(message: "Someething went wrong.")
    end
  end
end