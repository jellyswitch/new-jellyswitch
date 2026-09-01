# Guardrail (ADR 0019): an INCLUDED-room booking must have day-pass coverage for
# its date. Runs after the reuse/burn/buy steps; if the room is included and the
# member is still not covered (nobody reused/burned/bought), fail the booking so
# the organizer rolls it back — the controller surfaces this as a 422. Paid rooms
# and already-covered dates pass through untouched.
class Billing::Reservations::EnforceCoverage
  include Interactor

  delegate :reservation, :user, :location, to: :context

  def call
    # Opt-in: only the member self-service booking flow enforces coverage. Admin
    # / operator on-behalf bookings (which don't set this) keep their prior
    # behavior — an operator can still book an uncovered included room.
    return unless context.enforce_coverage

    room = reservation.room
    return if room.hourly_rate_in_cents.to_i > 0 || !room.include_with_day_pass?

    date = reservation.datetime_in.to_date
    # Evaluate against the ROOM's location, not the caller's current_location —
    # RedeemBundlePass mints the coverage pass against room.location, so at a
    # multi-location operator a mismatched current_location would burn a pass
    # and then fail the booking as "uncovered" anyway.
    state = Billing::Reservations::CoverageState.for(user: user, room: room, date: date,
                                                     location: room.location || location)
    return if state.outcome == :already_covered # a step just committed a pass, or they were covered

    context.fail!(
      message: "This room needs a day pass for #{date.strftime('%b %-d')}. Use a pass or buy one to book it.",
    )
  end
end
