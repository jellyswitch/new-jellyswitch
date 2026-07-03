class Billing::Reservations::UpdateRoomReservation
  include Interactor

  # Edits an upcoming reservation's start time / duration / room. The caller
  # (ReservationsController#update) guards the editable window (the 1-min
  # cutoff). This service re-validates the slot and re-prices.
  #
  # Re-pricing under capture-at-booking (ADR 0010): the original charge is
  # already captured, so an edit that costs MORE charges the delta
  # (ChargeExtensionDelta — a separate auto-capture for the difference). An edit
  # that costs the same or LESS is a no-op: member-initiated reductions
  # (shorten / switch to a cheaper room) do NOT auto-refund (ADR 0011) — a
  # refund happens only via a real cancel.
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
      # See SaveRoomReservation: :overlap-tagged failures surface as 409.
      context.conflict = reservation.errors.details[:base].any? { |d| d[:error] == :overlap }
      context.fail!(error: reservation.errors.full_messages.first || "Could not update reservation.")
      return
    end

    # A genuinely re-timed booking should notify once more — clear the per-channel
    # push markers so the rescheduled arrival/started jobs can claim and send
    # (Phase 6). Only on a real start-time change, so same-time edits (room/
    # duration only) stay deduped by the markers and never double-push.
    if reservation.saved_change_to_datetime_in?
      reservation.update_columns(arrival_notified_at: nil, started_notified_at: nil)
    end

    Billing::Reservations::ChargeExtensionDelta.call(context)
    if context.failure?
      context.error ||= context.message
      return
    end

    # datetime_in may have moved — re-queue the start reminder for the new time.
    Reservations::ScheduleUpcomingReservationReminder.call(context)
  end
end
