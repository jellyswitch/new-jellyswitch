module StripeUtils
  STRIPE_CLASSES = {
    invoice: 'Invoice',
    refund: 'Refund'
  }

  def retrieve_stripe_invoice(invoice)
    stripe_request(stripe_invoice, :retrieve, id: invoice.stripe_invoice_id)
  end

  def create_stripe_refund(invoice, stripe_invoice = nil)
    stripe_invoice = retrieve_stripe_invoice(invoice) unless stripe_invoice
    refund_args = { charge: stripe_invoice.charge, amount: invoice.amount_paid }

    stripe_request(stripe_refund, :create, refund_args)
  end

  private

  def stripe_invoice
    STRIPE_CLASSES[:invoice]
  end

  def stripe_refund
    STRIPE_CLASSES[:refund]
  end

  def stripe_request(klass, action, request_args)
    stripe_args = [request_args, operator_stripe_credentials]

    "Stripe::#{klass}".constantize.public_send(action, *stripe_args)
  end

  def operator_stripe_credentials
    {
      api_key: stripe_secret_key,
      stripe_account: stripe_user_id
    }
  end
end
