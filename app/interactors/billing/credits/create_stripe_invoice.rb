class Billing::Credits::CreateStripeInvoice
  include Interactor

  delegate :amount, :user, :location, to: :context

  def call
    invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id_for_location(location),
      currency: 'usd',
      amount: total_cost,
      description: "#{amount} credits at #{location.name}"
    }, {
      api_key: location.stripe_secret_key,
      stripe_account: location.stripe_user_id
    })

    invoice_args = CreditPurchaseFactory.for(user, location).invoice_args
    @invoice = Stripe::Invoice.create(
      invoice_args,
      {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id
      }
    )

    result = CreateInvoice.call(stripe_invoice: @invoice, location: location)
    if !result.success?
      context.fail!(message: result.message)
    end
  end

  def total_cost
    amount * location.credit_cost_in_cents
  end
end