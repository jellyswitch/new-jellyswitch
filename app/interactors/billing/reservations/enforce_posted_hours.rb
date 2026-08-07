# Business-hours rule (Nash incident, 2026-08-07): a member self-service
# booking must start AND end inside the room location's posted hours. The
# pickers (time_slots / booking_times / reserve_now) already bound what they
# OFFER; this is the single server-side backstop for what the API will ACCEPT,
# shared by the mobile API and the web member flow via both create organizers.
#
# Opt-in via enforce_posted_hours (mirrors enforce_coverage, ADR 0019): admin
# and operator on-behalf flows don't set it and keep booking anything. Members,
# leaseholders, and superadmins book 24/7 (books_outside_posted_hours?), and
# location staff are exempt.
class Billing::Reservations::EnforcePostedHours
  include Interactor

  def call
    return unless context.enforce_posted_hours

    params = context.reservation_params || {}
    room = params[:room]
    location = room&.location || context.location
    return if location.nil?

    user = context.user
    return if user.nil?
    return if user.books_outside_posted_hours?(location) || user.admin_or_manager?(location)

    datetime_in = params[:datetime_in]
    minutes = params[:minutes].to_i
    return if datetime_in.nil? || minutes <= 0

    # Time-of-day bound only (within_posted_hours?): the open_<day> flags mark
    # STAFFED days, and weekend daytime bookings by day-pass holders are
    # established behavior — don't block them.
    # end - 1 minute so a booking ending exactly at close passes (the window
    # check is exclusive of the close minute).
    datetime_out = datetime_in + minutes.minutes
    return if location.within_posted_hours?(datetime_in) &&
              location.within_posted_hours?(datetime_out - 1.minute)

    context.fail!(message: "#{location.name} is open #{location.posted_hours_label}. " \
                           "Rooms can be booked during open hours.")
  end
end
