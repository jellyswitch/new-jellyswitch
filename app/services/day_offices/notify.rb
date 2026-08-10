# The single place Day Office notifications are composed (ADR 0026). Every
# method only ENQUEUES — a job for the push, deliver_later for the mail — so a
# caller can hand off in a few hundred microseconds and never blocks a door
# opening on APNs.
#
# Two hard rules the callers rely on:
#
#   1. Never call these inside a `with_lock` block or any open transaction.
#      An enqueue that commits before the surrounding transaction does can
#      deliver a notification for work that then rolls back (and, with a real
#      queue backend, a job can start before the row it names is visible).
#      Every caller computes the outcome inside the lock and fires here after.
#   2. These are best-effort. A notification failure must never take down a
#      burn, a purchase, or a door unlock — so each method swallows and
#      reports its own errors, matching ChargeAtBooking#notify_charged.
#
# Nil-safe throughout: a nil pass/hold is a no-op, not a crash.
module DayOffices
  class Notify
    # A pool room was assigned. Fired from every path that produces a live
    # hold: the purchase organizers' tail step, the walk-in door burn, the
    # reserve-time coverage burn, and member self-serve scheduling.
    def self.assigned(day_pass:)
      return if day_pass.nil?

      SendNotificationsJob.perform_later(day_pass, "DayOfficeAssigned")
      UserMailer.day_office_confirmation(day_pass.id).deliver_later
    rescue => e
      report(e, "assigned", day_pass_id: day_pass&.id)
    end

    # Walk-in with no office left (decision #4): the pass burned and the door
    # opened, but the pool was full. Tell the member their access is fine, and
    # tell staff to fix it. No email — there is nothing to confirm.
    def self.walk_in_no_office(day_pass:)
      no_office(day_pass: day_pass, admin_type: "DayOfficeUnassignedAlert", method: "walk_in_no_office")
    end

    # Same shortfall reached from a reserve-time coverage burn: the member spent
    # a Day Office day on a room booking that may be weeks out, and the pool had
    # nothing free for that date. Nobody has arrived, so staff get the
    # date-bearing "booked" copy instead of the walk-in's "arrived".
    def self.booked_no_office(day_pass:)
      no_office(day_pass: day_pass, admin_type: "DayOfficeUnassignedBookingAlert", method: "booked_no_office")
    end

    # Staff moved the pass to a different room (Task 12). `hold` is the NEW
    # hold reservation; old_room_name is carried through for the email, which
    # names both rooms.
    def self.reassigned(hold:, old_room_name:)
      return if hold.nil?

      SendNotificationsJob.perform_later(hold, "DayOfficeReassigned")
      UserMailer.day_office_reassigned(hold.id, old_room_name).deliver_later
    rescue => e
      report(e, "reassigned", reservation_id: hold&.id)
    end

    # The admin alert is enqueued FIRST on purpose. If anything blows up
    # between the two enqueues, the failure mode has to be "staff were paged
    # but the member wasn't" — recoverable, because staff can go find them.
    # The reverse ("see staff" delivered, staff never told) strands a member at
    # a counter where nobody knows anything is wrong.
    def self.no_office(day_pass:, admin_type:, method:)
      return if day_pass.nil?

      SendNotificationsJob.perform_later(day_pass, admin_type)
      SendNotificationsJob.perform_later(day_pass, "DayOfficeUnavailable")
    rescue => e
      report(e, method, day_pass_id: day_pass&.id)
    end
    private_class_method :no_office

    def self.report(error, method, **context)
      Rails.logger.error("DayOffices::Notify.#{method} failed: #{error.class}: #{error.message}")
      Honeybadger.notify(error, context: context) rescue nil
      nil
    end
    private_class_method :report
  end
end
