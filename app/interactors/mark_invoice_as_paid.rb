class MarkInvoiceAsPaid
  include Interactor

  def call
    invoice = Invoice.find(context.invoice_id)
    stripe_invoice = invoice.stripe_invoice

    if stripe_invoice.customer != context.user.stripe_customer_id
      context.fail!(message: "Invalid invoice.")
    end

    begin
      stripe_invoice.pay({paid_out_of_band: true})
    rescue => e
      context.fail!(message: e.message)
    end
    invoice.update(status: "paid")
    context.invoice = invoice
  end
end