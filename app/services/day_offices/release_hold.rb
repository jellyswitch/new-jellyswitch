# The one way an office hold is released (refund cascade, cancel-scheduled-day,
# pass destroy). Cancelling — not destroying — matches CancelReservation's
# convention and frees the room via Reservation's default_scope.
#
# update_columns, not update!: release must never fail. ReservationValidator's
# overlap check is guarded by `return if record.cancelled?` (checked against
# the in-memory value, so it never fires here) — but Reservation also runs
# attendee_count_within_capacity on EVERY save, cancel included, and that one
# is not cancelled-gated. A hold whose room capacity was edited down after
# booking (e.g. an admin drops it to 0) would fail that validation and raise
# RecordInvalid mid-refund-cascade for a save that only wants to free the room.
# update_columns skips validations and callbacks entirely, so releasing a hold
# can never be blocked by drift in the room it points at.
module DayOffices
  class ReleaseHold
    def self.call(hold)
      return if hold.nil? || hold.cancelled?
      hold.update_columns(cancelled: true, updated_at: Time.current)
    end
  end
end
