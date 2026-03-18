module RecurringReservations
  class Create
    include Interactor

    def call
      recurring = build_recurring_reservation
      dates = recurring.occurrence_dates

      if dates.empty?
        context.fail!(message: "No valid dates found for the selected recurrence pattern and period.")
        return
      end

      # Pre-check ALL dates for conflicts
      conflicts = check_all_conflicts(recurring, dates)
      if conflicts.any?
        context.conflicts = conflicts
        context.fail!(message: "Cannot create recurring reservation. #{conflicts.size} date(s) have scheduling conflicts.")
        return
      end

      # All clear - create everything in a transaction
      ActiveRecord::Base.transaction do
        recurring.save!
        dates.each do |date|
          create_occurrence(recurring, date)
        end
      end

      context.recurring_reservation = recurring
    rescue ActiveRecord::RecordInvalid => e
      context.fail!(message: e.message)
    end

    private

    def build_recurring_reservation
      RecurringReservation.new(
        user: context.user,
        room: context.room,
        operator: context.room.operator,
        location: context.room.location,
        title: context.title,
        recurrence_pattern: context.recurrence_pattern,
        duration_minutes: context.duration_minutes,
        time_of_day: context.time_of_day,
        day_of_week: context.day_of_week,
        day_of_month: context.day_of_month,
        start_date: context.start_date,
        end_date: context.end_date
      )
    end

    def check_all_conflicts(recurring, dates)
      room = recurring.room
      zone = ActiveSupport::TimeZone[room.location.time_zone] || Time.zone
      conflicts = []

      # Batch-fetch all existing reservations for this room in the date range
      range_start = zone.local(dates.first.year, dates.first.month, dates.first.day, 0, 0)
      range_end = zone.local(dates.last.year, dates.last.month, dates.last.day, 23, 59)
      existing = room.reservations.where(cancelled: false)
                     .overlapping(range_start, range_end + 1.day)
                     .pluck(:datetime_in, :minutes)

      dates.each do |date|
        start_time = zone.local(date.year, date.month, date.day,
                                recurring.time_of_day.hour, recurring.time_of_day.min)
        end_time = start_time + recurring.duration_minutes.minutes

        # Check against existing reservations in memory
        has_conflict = existing.any? do |res_start, res_minutes|
          res_end = res_start + res_minutes.minutes
          start_time < res_end && end_time > res_start
        end

        if has_conflict
          conflicts << { date: date, time: start_time }
        end
      end

      conflicts
    end

    def create_occurrence(recurring, date)
      zone = ActiveSupport::TimeZone[recurring.room.location.time_zone] || Time.zone
      datetime_in = zone.local(date.year, date.month, date.day,
                               recurring.time_of_day.hour, recurring.time_of_day.min)

      Reservation.create!(
        user: recurring.user,
        room: recurring.room,
        datetime_in: datetime_in,
        hours: recurring.duration_minutes / 60,
        minutes: recurring.duration_minutes,
        paid: false,
        note: recurring.title,
        recurring_reservation_id: recurring.id
      )
    end
  end
end
