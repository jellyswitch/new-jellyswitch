class Billing::Reservations::UpdateRoomReservation
  include Interactor

  # Edits an upcoming (not-yet-started, not-yet-captured) reservation's
  # start time and/or duration. The caller (ReservationsController#update)
  # guards the "still editable" window; this service re-validates the slot,
  # re-prices the hold, and reschedules the start-time-bound jobs.
  #
  # Re-pricing reuses the extension billing path: set `is_extend` so
  # AuthorizeHold cancels the prior hold and re-authorizes for the new
  # total (computed by ChargeCalculator). Shortening re-authorizes lower;
  # a now-free booking releases the hold entirely. captured_at is blank
  # (the controller blocks started/charged reservations), so the
  # post-capture ChargeExtensionDelta branch never applies here.
  def call
    reservation = context.reservation

    # Validate + persist the new window. ReservationValidator's overlap
    # check excludes this record's own id, so keeping/extending the same
    # slot is fine; clashing with a *different* booking fails the save and
    # leaves the persisted row untouched (assign_attributes is in-memory).
    reservation.assign_attributes(
      room: context.new_room || reservation.room,
      datetime_in: context.new_datetime_in,
      minutes: context.new_minutes,
    )

    unless reservation.save
      context.fail!(error: reservation.errors.full_messages.first || "Could not update reservation.")
      return
    end

    context.is_extend = true
    Billing::Reservations::AuthorizeHoldOrSchedule.call(context)
    if context.failure?
      context.error ||= context.message
      return
    end

    # datetime_in may have moved — re-queue the capture and reminders for
    # the new start. SettleReservationJob ignores stale early fires, so the
    # leftover job at the old start is harmless.
    Reservations::ScheduleSettleReservation.call(context)
    Reservations::ScheduleUpcomingReservationReminder.call(context)
  end
end
