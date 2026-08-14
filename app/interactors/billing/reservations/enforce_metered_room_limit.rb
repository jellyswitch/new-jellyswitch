# A day pass's included-meeting-room-minutes cap is normally enforced as MONEY:
# minutes past the allowance bill at the location's overage rate
# (ChargeCalculator#day_pass_overage_cents), and capture-at-booking demands a
# card. Where the location has NO overage rate (overage_rate_in_cents 0/nil)
# that enforcement evaporates — the overage prices to $0, no payment is asked,
# and a "limited" pass books unlimited call-room time (Untethered Fulton: a
# free-pass holder with no card on file booked 3.5h; the location's own
# 120-minute pack limits were equally fictional).
#
# This guard makes a configured cap real when money can't: a member self-serve
# booking of a $0 room that would exceed the covering metered pass's remaining
# allowance, at a location with no overage rate, is blocked (422) instead of
# sailing through free.
#
# Scope, deliberately narrow:
#   * enforce_coverage flag only — the same member-self-serve opt-in as
#     EnforceCoverage. Staff / admin on-behalf bookings stay uncapped by design.
#   * Metered DAY PASSES only (has_meeting_room_limit?). Unmetered passes and
#     plan/subscription allowances keep today's behavior.
#   * Locations WITH an overage rate are untouched — there the limit is already
#     enforced as billable overage, which is the product working as designed.
#
# Runs after EnforceCoverage, so a pass minted by the coverage steps
# (reuse/burn/buy) this same request is already in place to read.
class Billing::Reservations::EnforceMeteredRoomLimit
  include Interactor

  delegate :reservation, :user, :location, to: :context

  def call
    return unless context.enforce_coverage

    room = reservation.room
    return if room.hourly_rate_in_cents.to_i > 0 # priced rooms bill their own hourly rate

    rate_location = room.location || location
    return if rate_location.overage_rate_in_cents.to_i > 0 # billable overage — ChargeCalculator handles it

    date = reservation.datetime_in.to_date
    # Same pass ChargeCalculator's metered branch would price against.
    day_pass_type = user.day_passes.where(day: date).first&.day_pass_type
    return unless day_pass_type&.has_meeting_room_limit?

    over = Billing::Reservations::OveragePreview.over_minutes(
      user: user, date: date, minutes: reservation.minutes,
      day_pass_type: day_pass_type, reservation_id: reservation.id,
    )
    return if over <= 0

    context.fail!(
      message: "Your #{day_pass_type.name} includes " \
               "#{day_pass_type.included_meeting_room_minutes} minutes of meeting room " \
               "time for the day, and this booking would go #{over} minutes over. " \
               "Book a shorter time, or ask the front desk.",
    )
  end
end