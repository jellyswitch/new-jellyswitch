class Billing::Invoices::Custom::CreateInvoice
  include Interactor

  delegate :billable, :amount, :description, to: :context

  def call
    dollars = Money.from_amount(amount.to_i, "USD")
    amount_in_cents = dollars.cents

    @invoice_item = Stripe::InvoiceItem.create({
      customer: billable.stripe_customer_id,
      currency: 'usd',
      amount: amount_in_cents,
      description: description
    }, {
      api_key: billable.operator.stripe_secret_key,
      stripe_account: billable.operator.stripe_user_id
    })

    invoice_args = {
      customer: billable.stripe_customer_id,
      auto_advance: true
    }

    if billable.out_of_band?
      invoice_args = invoice_args.merge!(
        {
          billing: 'send_invoice',
          days_until_due: 30
        }
      )
    else
      invoice_args = invoice_args.merge!(
        billing: 'charge_automatically'
      )
    end


    @invoice = Stripe::Invoice.create(
      invoice_args,
      {
        api_key: billable.operator.stripe_secret_key,
        stripe_account: billable.operator.stripe_user_id
      }
    )

    result = ::CreateInvoice.call(stripe_invoice: @invoice)
    if !result.success?
      context.fail!(message: result.message)
    end
  end
end