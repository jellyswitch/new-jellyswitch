class MarkInvoiceAsPaid
  include Interactor

  def call
    invoice = Stripe::Invoice.retrieve(context.invoice_id)

    if invoice.customer != context.user.stripe_customer_id
      context.fail!(message: "Invalid invoice.")
    end

    invoice.pay({paid_out_of_band: true})
    context.invoice = invoice
  rescue Exception => e
    context.fail!(message: e.message)
  end
end