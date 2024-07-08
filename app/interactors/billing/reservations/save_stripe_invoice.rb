class Billing::Reservations::SaveStripeInvoice
  include Interactor

  delegate :user, :reservation, :is_extend, :additional_duration, to: :context

  def call
    location = reservation.room.location
    operator = location.operator
    reservation_day = reservation.datetime_in.to_date

    charge_amount = reservation.charge_amount

    if is_extend
      charge_amount = ((reservation.room.hourly_rate_in_cents / 60.0) * additional_duration).to_i
    end

    if charge_amount.positive?
      @invoice_item = Stripe::InvoiceItem.create({
        customer: reservation.user.stripe_customer_id,
        currency: "usd",
        amount: charge_amount,
        description: reservation.charge_description,
      }, {
        api_key: operator.stripe_secret_key,
        stripe_account: operator.stripe_user_id,
      })

      invoice_args = ReservableFactory.for(reservation).invoice_args
      @invoice = Stripe::Invoice.create(
        invoice_args,
        {
          api_key: operator.stripe_secret_key,
          stripe_account: operator.stripe_user_id,
        }
      )

      result = CreateInvoice.call(stripe_invoice: @invoice)
      if !result.success?
        context.fail!(message: result.message)
      end

      context.invoice = @invoice
    end
  end
end
