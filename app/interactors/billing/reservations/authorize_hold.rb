# Places a Stripe authorization hold for the expected MAX charge on
# this reservation, instead of capturing up-front. CaptureHold later
# settles the actual amount based on minutes used and releases the
# rest of the hold.
#
# Runs in the CreateRoomReservation organizer in place of the old
# SaveStripeInvoice + ChargeReservationInvoice steps when the booking
# would otherwise be charged to the user's card.
class Billing::Reservations::AuthorizeHold
  include Interactor

  delegate :user, :reservation, :is_extend, :additional_duration, to: :context

  def call
    return if is_extend # extensions still use the legacy invoice path
    return if user.out_of_band?

    location = reservation.room.location
    amount = expected_max_charge
    return unless amount.positive?

    stripe_customer_id = user.stripe_customer_id_for_location(location)
    unless stripe_customer_id
      context.fail!(message: 'No Stripe customer on file for this location.')
      return
    end

    pm_id = default_payment_method(stripe_customer_id, location)
    unless pm_id
      context.fail!(message: 'No payment method on file. Please add a card and try again.')
      return
    end

    intent = Stripe::PaymentIntent.create(
      {
        amount: amount,
        currency: 'usd',
        customer: stripe_customer_id,
        payment_method: pm_id,
        capture_method: 'manual',
        confirm: true,
        off_session: true,
        description: reservation.charge_description,
        metadata: {
          reservation_id: reservation.id,
          expected_max_amount: amount,
        },
      },
      {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id,
      },
    )

    reservation.update!(
      stripe_payment_intent_id: intent.id,
      authorized_amount_in_cents: amount,
      paid: true, # marks as billed; settled amount set on capture
    )
    context.payment_intent = intent
  rescue Stripe::CardError => e
    context.fail!(message: "Card error: #{e.message}")
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e)
    context.fail!(message: 'Could not place a hold on your card. Please try again.')
  end

  private

  def expected_max_charge
    # Same calc as SaveStripeInvoice — what would have been charged
    # up-front. CaptureHold will compute the real amount from actual
    # minutes used.
    base = context.overage_charge_amount || reservation.charge_amount

    discount_code = context.discount_code
    if discount_code.present? && base.positive?
      discount_amount = discount_code.calculate_discount(base)
      base -= discount_amount
      context.discount_amount_in_cents = discount_amount
    end
    [base, 0].max.to_i
  end

  def default_payment_method(customer_id, location)
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
    customer = Stripe::Customer.retrieve(customer_id, creds)
    ds = customer.try(:default_source)
    return ds if ds.is_a?(String) && ds.present?
    pm_id = customer.try(:invoice_settings)&.try(:default_payment_method)
    return pm_id if pm_id.is_a?(String) && pm_id.present?

    pms = Stripe::PaymentMethod.list({ customer: customer_id, type: 'card', limit: 1 }, creds)
    pms.data.first&.id
  end
end
