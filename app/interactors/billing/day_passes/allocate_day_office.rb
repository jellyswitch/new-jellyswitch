
# Runs right after SaveDayPass in every purchase organizer: allocation must
# succeed BEFORE money moves, and its rollback rides the organizer's unwind.
# (The pass's before_destroy would release the hold anyway when SaveDayPass
# rolls back — this rollback is the explicit, order-correct release.)
class Billing::DayPasses::AllocateDayOffice
  include Interactor

  delegate :day_pass, to: :context

  def call
    return unless day_pass&.day_office?

    hold = DayOffices::Allocator.allocate!(day_pass: day_pass)
    if hold.nil?
      # outcome: :sold_out matches the ScheduleDay/bundle vocabulary the api
      # controller already cases on (result.outcome). The fallback standard
      # type is NOT threaded through this context — the controller derives
      # it itself (DayPassType.suggested_standard_for(current_location)),
      # since it needs the request's current_location, not day_pass.location
      # (nil for a legacy pass whose type has no location of its own).
      context.fail!(
        outcome: :sold_out,
        message: "#{day_pass.day_pass_type.name.pluralize} are fully booked for " \
                 "#{day_pass.day.strftime('%B %e')}. Try another day."
      )
    end
    context.office_hold = hold
  end

  def rollback
    DayOffices::ReleaseHold.call(context.office_hold)
  end
end
