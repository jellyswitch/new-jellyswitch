class CreateInvoice
  include Interactor

  delegate :stripe_invoice, to: :context

  def call
    invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
    if invoice.present?
      context.fail!(message: "Invoice #{invoice.number} already exists")
    end

    customer = stripe_invoice.customer

    # TODO: put type in stripe invoice metadata
    billable = User.find_by(stripe_customer_id: customer) || Organization.find_by(stripe_customer_id: customer)

    if billable.nil?
      context.fail!(message: "Cannot find billable with stripe customer id #{customer}")
    end

    invoice_date = Time.at(stripe_invoice.date).to_datetime

    due_date = nil
    if stripe_invoice.due_date.present?
      due_date = Time.at(stripe_invoice.due_date).to_datetime
    end

    invoice = Invoice.create!(
      billable: billable,
      operator_id: billable.operator.id,
      amount_due: stripe_invoice.amount_due.to_i,
      amount_paid: stripe_invoice.amount_paid.to_i,
      number: stripe_invoice.number,
      stripe_invoice_id: stripe_invoice.id,
      date: invoice_date,
      due_date: due_date,
      status: stripe_invoice.status
    )

    context.invoice = invoice
  end
end
