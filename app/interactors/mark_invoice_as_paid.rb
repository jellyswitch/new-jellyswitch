class MarkInvoiceAsPaid
  include Interactor

  def call
    invoice = Invoice.find(context.invoice_id).stripe_invoice

    if invoice.customer != context.user.stripe_customer_id
      context.fail!(message: "Invalid invoice.")
    end

    invoice.pay({paid_out_of_band: true})
    invoice.update(status: "paid")
    context.invoice = invoice
  end
end