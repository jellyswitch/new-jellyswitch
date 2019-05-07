class Billing::DayPasses::CreateStripeInvoice
  include Interactor

  delegate :day_pass, :token, :operator, :out_of_band, :params, :user_id, :user, to: :context

  def call
    @invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id,
      currency: 'usd',
      amount: day_pass.day_pass_type.amount_in_cents,
      description: day_pass.charge_description
    }, {
      api_key: operator.stripe_secret_key,
      stripe_account: operator.stripe_user_id
    })

    if token && !(out_of_band || user.out_of_band)
      @invoice = Stripe::Invoice.create({
        customer: user.stripe_customer_id,
        billing: 'send_invoice',
        days_until_due: 30,
        auto_advance: true
      }, {
        api_key: operator.stripe_secret_key,
        stripe_account: operator.stripe_user_id
      })
    else
      @invoice = Stripe::Invoice.create({
        customer: user.stripe_customer_id,
        billing: 'charge_automatically',
        auto_advance: true
      }, {
        api_key: operator.stripe_secret_key,
        stripe_account: operator.stripe_user_id
      })
    end

    result = CreateInvoice.call(stripe_invoice: @invoice)
    if !result.success?
      context.fail!(message: result.message)
    end

    day_pass.invoice_id = result.invoice.id
    if !day_pass.save
      context.fail!(message: "There was a problem invoicing this day pass.")
    end

    context.day_pass = day_pass
    context.notifiable = day_pass
  end
end