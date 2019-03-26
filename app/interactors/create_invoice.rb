class CreateInvoice
  include Interactor

  def call
    stripe_invoice = context.stripe_invoice

    invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
    if invoice.present?
      context.fail!(message: "Invoice #{invoice.number} already exists")
    end

    user = User.find_by(stripe_customer_id: stripe_invoice.customer)
    if user.nil?
      context.fail!(message: "Cannot find user with stripe customer id #{stripe_invoice.customer}")
    end

    invoice_date = Time.at(stripe_invoice.date).to_datetime

    due_date = nil
    if stripe_invoice.due_date.present?
      due_date = Time.at(stripe_invoice.due_date).to_datetime
    end

    invoice = Invoice.create!(
      user_id: user.id,
      operator_id: user.operator.id,
      amount_due: stripe_invoice.amount_due.to_i,
      amount_paid: stripe_invoice.amount_paid.to_i,
      number: stripe_invoice.number,
      stripe_invoice_id: stripe_invoice.id,
      date: invoice_date,
      due_date: due_date,
      status: stripe_invoice.status
    )

    context.invoice = invoice
  rescue Exception => e
    Rollbar.error("Interactor Failure: #{e.message}")
    context.fail!(message: e.message)
  end
end

# == Schema Information
#
# Table name: invoices
#
#  id                :bigint(8)        not null, primary key
#  amount_due        :integer
#  amount_paid       :integer
#  date              :datetime
#  number            :string
#  status            :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operator_id       :integer
#  stripe_invoice_id :string
#  user_id           :integer
#