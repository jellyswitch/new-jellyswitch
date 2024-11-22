class Billing::Reservations::SaveStripeInvoice
  include Interactor

  delegate :user, :reservation, :is_extend, :additional_duration, to: :context

  def call
    location = reservation.room.location
    reservation_day = reservation.datetime_in.to_date

    charge_amount = reservation.charge_amount

    if is_extend
      charge_amount = reservation.additional_duration_price(additional_duration)
    end

    if charge_amount.positive?
      @invoice_item = Stripe::InvoiceItem.create({
        customer: reservation.user.stripe_customer_id,
        currency: "usd",
        amount: charge_amount,
        description: reservation.charge_description,
      }, {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id,
      })

      invoice_args = ReservableFactory.for(reservation).invoice_args
      @invoice = Stripe::Invoice.create(
        invoice_args,
        {
          api_key: location.stripe_secret_key,
          stripe_account: location.stripe_user_id,
        }
      )

      result = CreateInvoice.call(stripe_invoice: @invoice, location: location)
      if !result.success?
        context.fail!(message: result.message)
      end

      context.invoice = @invoice
    end
  end
end
