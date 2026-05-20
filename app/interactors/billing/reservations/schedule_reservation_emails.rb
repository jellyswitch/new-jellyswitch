class Billing::Reservations::ScheduleReservationEmails
  include Interactor

  def call
    # Reservation drip emails (reservation_onboarding +
    # reservation_follow_up via ProductEmailTemplate) are designed for
    # one-off paid bookers: people who pay an hourly rate for a meeting
    # room, or hit overage on their plan / day pass. Members, office
    # members (lease holders), admins, GMs, CMs, and superadmins all
    # have `reservation.paid == false` (see
    # User#should_charge_for_reservation? in concerns/permissions.rb).
    # Sending them post-booking nudges is noise — gate strictly on the
    # paid flag.
    return unless context.reservation&.paid?

    context.product_email_sendable = context.reservation
    context.product_email_type = "reservation"
    context.product_email_user = context.reservation.user

    ScheduleProductEmails.call(context)
  end
end
