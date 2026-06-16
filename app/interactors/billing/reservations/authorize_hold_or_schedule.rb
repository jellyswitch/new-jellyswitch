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
      # An edit can push a reservation that already carries a hold past the
      # auth horizon. The deferred job won't touch a reservation that still
      # has a PI, and that manual-capture hold would expire before the new
      # (far) start — so release it now and let the job re-authorize ~6 days
      # out. (On a plain booking there's no prior hold, so this is a no-op.)
      release_stale_hold if context.is_extend && reservation.stripe_payment_intent_id.present? && reservation.captured_at.blank?

      AuthorizeReservationHoldJob
        .set(wait_until: reservation.datetime_in - AUTH_HORIZON)
        .perform_later(reservation.id)
    end
  end

  private

  def release_stale_hold
    location = reservation.room.location
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
    begin
      Stripe::PaymentIntent.cancel(reservation.stripe_payment_intent_id, {}, creds)
    rescue Stripe::InvalidRequestError => e
      Rails.logger.warn("AuthorizeHoldOrSchedule: could not cancel prior PI #{reservation.stripe_payment_intent_id}: #{e.message}")
    ensure
      reservation.update!(stripe_payment_intent_id: nil, authorized_amount_in_cents: nil)
    end
  end
end
