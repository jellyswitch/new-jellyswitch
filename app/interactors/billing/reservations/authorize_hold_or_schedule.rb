class Billing::Reservations::AuthorizeHoldOrSchedule
  include Interactor

  # Stripe manual-capture PaymentIntents auto-cancel after ~7 days, so
  # holds placed at booking time for far-future bookings would expire
  # before SettleReservationJob fires. For close bookings (within
  # ~6 days of datetime_in) we authorize immediately, same as before.
  # For everything else we defer to AuthorizeReservationHoldJob, which
  # runs at datetime_in - 6 days and places the hold then.
  #
  # AuthorizeHold (whether called inline or via the job) decides for
  # itself whether the reservation actually needs a hold (it bails for
  # zero amounts and out-of-band users), so we don't pre-filter here.
  AUTH_HORIZON = 6.days.freeze

  delegate :reservation, to: :context

  def call
    return if reservation.user.out_of_band?

    if reservation.datetime_in <= Time.current + AUTH_HORIZON
      Billing::Reservations::AuthorizeHold.call(context)
    else
      AuthorizeReservationHoldJob
        .set(wait_until: reservation.datetime_in - AUTH_HORIZON)
        .perform_later(reservation.id)
    end
  end
end
