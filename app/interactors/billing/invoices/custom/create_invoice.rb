class Billing::Invoices::Custom::CreateInvoice
  include Interactor

  delegate :user, :amount, :description, to: :context

  def call
    dollars = Money.from_amount(amount.to_i, "USD")
    amount_in_cents = dollars.cents

    @invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id,
      currency: 'usd',
      amount: amount_in_cents,
      description: description
    }, {
      api_key: user.operator.stripe_secret_key,
      stripe_account: user.operator.stripe_user_id
    })

    @invoice = Stripe::Invoice.create(
      {
        customer: user.stripe_customer_id,
        auto_advance: true
      },
      {
        api_key: user.operator.stripe_secret_key,
        stripe_account: user.operator.stripe_user_id
      }
    )

    result = ::CreateInvoice.call(stripe_invoice: @invoice)
    if !result.success?
      context.fail!(message: result.message)
    end
  end
end