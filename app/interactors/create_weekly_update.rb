class CreateWeeklyUpdate
  include Interactor
  delegate :week_start, :week_end, :operator, to: :context

  def call
    weekly_update = WeeklyUpdate.from_weekly_report(Jellyswitch::WeeklyReport.new(operator, week_start, week_end))
    if weekly_update.save
      context.weekly_update = weekly_update
    else
      context.fail!(message: "Someething went wrong.")
    end
  end
end