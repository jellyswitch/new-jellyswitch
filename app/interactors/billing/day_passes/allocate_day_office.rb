
# Runs right after SaveDayPass in every purchase organizer: allocation must
# succeed BEFORE money moves, and its rollback rides the organizer's unwind.
# (The pass's before_destroy would release the hold anyway when SaveDayPass
# rolls back — this rollback is the explicit, order-correct release.)
class Billing::DayPasses::AllocateDayOffice
  include Interactor

  delegate :day_pass, to: :context

  def call
    return unless day_pass&.day_office?

    hold = begin
      DayOffices::Allocator.allocate!(day_pass: day_pass)
    rescue ActiveRecord::RecordInvalid => e
      # The allocator deliberately re-raises anything that isn't an overlap
      # loss (e.g. a pool room with capacity 0) so a config error can't hide
      # behind "sold out". Here it becomes a staff-actionable message rather
      # than a stack trace on the admin's screen. Not :sold_out, so the API
      # doesn't offer the swap-to-standard fallback for a config problem.
      context.fail!(
        outcome: :misconfigured,
        message: day_pass.day_pass_type.office_pool_problem ||
                 "Couldn't hold an office: #{e.record.errors.full_messages.to_sentence}.",
      )
    end
    if hold.nil?
      # outcome: :sold_out matches the ScheduleDay/bundle vocabulary the api
      # controller already cases on (result.outcome). The fallback standard
      # type is NOT threaded through this context — the controller derives
      # it itself (DayPassType.suggested_standard_for(current_location)),
      # since it needs the request's current_location, not day_pass.location
      # (nil for a legacy pass whose type has no location of its own).
      context.fail!(
        outcome: :sold_out,
        message: day_pass.day_pass_type.sold_out_message(day_pass.day),
      )
    end
    context.office_hold = hold
  end

  def rollback
    DayOffices::ReleaseHold.call(context.office_hold)
  end
end
