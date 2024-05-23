class Billing::Reservations::SaveStripeInvoice
  include Interactor

  delegate :user, :reservation, to: :context

  def call
    location = reservation.room.location
    operator = location.operator
    reservation_day = reservation.datetime_in.to_date

    if user.should_charge_for_reservation?(location, reservation_day)
      @invoice_item = Stripe::InvoiceItem.create({
        customer: reservation.user.stripe_customer_id,
        currency: "usd",
        amount: reservation.charge_amount,
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
