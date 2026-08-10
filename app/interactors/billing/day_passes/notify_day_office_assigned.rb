# The LAST step of every day-pass purchase organizer (ADR 0026). Deliberately
# not part of Billing::DayPasses::AllocateDayOffice, which runs second: the
# hold is taken before money moves, and a charge that declines afterwards
# unwinds the whole purchase. An email sent from there could not be unsent, so
# the member would have a written confirmation for an office they never bought.
# Running last means "we told them" implies "the charge cleared."
#
# No rollback — nothing after this step can fail, and an enqueued email is not
# something a rollback could take back anyway.
class Billing::DayPasses::NotifyDayOfficeAssigned
  include Interactor

  delegate :day_pass, to: :context

  def call
    return unless day_pass&.day_office?

    # reload_office_hold, not office_hold: earlier steps in this same request
    # (serializers, the allocator's own idempotency probe) can seed Rails'
    # per-request query cache with a stale answer for this association. Read
    # through to the DB so a hold released mid-organizer really reads as gone.
    return unless day_pass.reload_office_hold

    DayOffices::Notify.assigned(day_pass: day_pass)
  end
end
