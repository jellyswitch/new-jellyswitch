class UpdateInvoiceStatus
  include Interactor

  def call
    stripe_invoice = context.stripe_invoice

    invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
    if invoice.nil?
      context.fail!(message: "Can't find invoice #{stripe_invoice.id}")
    end

    new_status = stripe_invoice.status

    invoice.status = new_status

    if !invoice.save
      context.fail!(message: "Couldn't save invoice #{number} with new status: #{new_status}")
    end
  rescue Exception => e
    context.fail!(message: e.message)
  end
end