class Billing::Credits::CreateStripeInvoice
  include Interactor

  delegate :amount, :user, :location, to: :context

  def call
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    invoice_item = Stripe::InvoiceItem.create({
      customer: user.stripe_customer_id_for_location(location),
      currency: 'usd',
      amount: total_cost,
      description: "#{amount} credits at #{location.name}"
    }, creds)

    invoice_args = CreditPurchaseFactory.for(user, location).invoice_args
    @invoice =
      begin
        Stripe::Invoice.create(invoice_args, creds)
      rescue Stripe::StripeError
        # Invoice creation failed after the item was created — delete the pending
        # item so it isn't swept into the member's NEXT invoice as a phantom
        # charge (this interactor has no rollback to clean it up otherwise).
        Stripe::InvoiceItem.delete(invoice_item.id, creds) rescue nil
        raise
      end

    result = CreateInvoice.call(stripe_invoice: @invoice, location: location)
    if !result.success?
      context.fail!(message: result.message)
    end
  end

  def total_cost
    amount * location.credit_cost_in_cents
  end
end