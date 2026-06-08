class WeeklyUpdates::Save
  include Interactor
  delegate :week_start, :week_end, :operator, :location, to: :context

  def call
    # Idempotent: exactly one weekly update per (location, week_start). The job
    # processes every operator × location in a single pass, so a mid-batch
    # failure + Sidekiq retry (or a double-firing scheduler) would otherwise
    # re-create an update — and a duplicate feed card — for every location it
    # already handled. If one exists, return it WITHOUT setting
    # context.notifiable, so CreateNotifications doesn't post another card.
    existing = WeeklyUpdate.find_by(location_id: location.id, week_start: week_start)
    if existing
      context.weekly_update = existing
      return
    end

    weekly_report = Jellyswitch::WeeklyReport.new(operator, location, week_start, week_end)
    previous_weekly_report = Jellyswitch::WeeklyReport.new(operator, location, week_start - 1.week, week_end - 1.week)

    weekly_update = WeeklyUpdate.from_weekly_reports(weekly_report, previous_weekly_report)

    if weekly_update.save
      context.weekly_update = weekly_update
      context.notifiable = weekly_update
    else
      context.fail!(message: "Something went wrong.")
    end
  rescue ActiveRecord::RecordNotUnique
    # Lost a race with a concurrent run — the unique index on
    # (location_id, week_start) held. Treat as already-created; no new card.
    context.weekly_update = WeeklyUpdate.find_by(location_id: location.id, week_start: week_start)
  end
end