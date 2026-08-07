# Duration backstop for member self-serve bookings (prod audit 2026-08-07: a
# hand-rolled POST to the web member form could book past the slider's bounds —
# the mobile API has capped duration in-controller since the 2026-07 policy
# fix, but the web member #create posted straight to the organizers with no
# server-side check). Opt-in via enforce_duration_cap (mirrors
# enforce_coverage, ADR 0019): the staff calendar / on-behalf flows don't set
# it — context.user is the bookED member there, not the staff booker, and
# staff legitimately book up to the 12h admin allowance.
class Billing::Reservations::EnforceDurationCap
  include Interactor

  def call
    return unless context.enforce_duration_cap

    params = context.reservation_params || {}
    room = params[:room]
    return if room.nil?

    minutes = params[:minutes].to_i
    return if minutes <= 0

    # In the flows that set the flag, context.user IS the booker — staff
    # booking themselves keep the admin allowance, same as the API's
    # staff_booker? check.
    user = context.user
    location = room.location || context.location
    admin = user.present? && location.present? && user.admin_or_manager?(location)
    cap = room.max_bookable_minutes(admin: admin)
    return if minutes <= cap

    context.fail!(message: "#{room.name} can be booked for up to #{cap / 60} hours.")
  end
end
