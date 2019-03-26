class MarkInvoiceAsPaid
  include Interactor

  def call
    invoice = Invoice.find(context.invoice_id).stripe_invoice

    if invoice.customer != context.user.stripe_customer_id
      context.fail!(message: "Invalid invoice.")
    end

    invoice.pay({paid_out_of_band: true})
    context.invoice = invoice
  rescue Exception => e
    Rollbar.error("Interactor Failure: #{e.message}")
    context.fail!(message: e.message)
  end
end