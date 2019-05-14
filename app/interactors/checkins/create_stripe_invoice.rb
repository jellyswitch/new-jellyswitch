class Checkins::CreateStripeInvoice
  include Interactor

  delegate :checkin, to: :context

  def call
    @invoice_item = Stripe::InvoiceItem.create({
      customer: checkin.user.stripe_customer_id,
      currency: 'usd',
      amount: 300,
      description: checkin.charge_description
    }, {
      api_key: checkin.location.operator.stripe_secret_key,
      stripe_account: checkin.location.operator.stripe_user_id
    })

    if checkin.user.has_billing?
      @invoice = Stripe::Invoice.create({
        customer: checkin.user.stripe_customer_id,
        billing: 'send_invoice',
        days_until_due: 30,
        auto_advance: true
      }, {
        api_key: checkin.location.operator.stripe_secret_key,
        stripe_account: checkin.location.operator.stripe_user_id
      })
    else
      @invoice = Stripe::Invoice.create({
        customer: checkin.user.stripe_customer_id,
        billing: 'charge_automatically',
        auto_advance: true
      }, {
        api_key: checkin.location.operator.stripe_secret_key,
        stripe_account: checkin.location.operator.stripe_user_id
      })
    end

    result = CreateInvoice.call(stripe_invoice: @invoice)
    if !result.success?
      context.fail!(message: result.message)
    end

    if !checkin.update(invoice_id: result.invoice.id)
      context.fail!(message: "There was a problem invoicing this day pass.")
    end
  end
end