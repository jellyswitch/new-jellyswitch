
class UpdateInvoiceStatus
  include Interactor

  delegate :stripe_invoice, to: :context

  def call
    invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
    if invoice.nil?
      context.fail!(message: "Can't find invoice #{stripe_invoice.id}")
    end

    new_status = stripe_invoice.status

    # Stripe event payloads are frozen snapshots and delivery is at-least-once
    # and unordered — a replayed invoice.payment_failed carries status "open"
    # even after the member has paid. A settled invoice never legitimately goes
    # back to open, so treat that as a stale snapshot and no-op (success, not
    # fail! — the webhook should still 200 so Stripe stops redelivering).
    return if %w(paid refunded void).include?(invoice.status) && new_status == "open"

    invoice.status = new_status
    # Keep the money fields in sync — this used to update only status, so
    # amount_paid stayed at its creation-time value (usually 0) forever and
    # rows created before Stripe set dates never got them.
    invoice.amount_due = stripe_invoice.amount_due.to_i unless stripe_invoice.try(:amount_due).nil?
    invoice.amount_paid = stripe_invoice.amount_paid.to_i unless stripe_invoice.try(:amount_paid).nil?
    invoice.due_date ||= Time.at(stripe_invoice.due_date).to_datetime if stripe_invoice.try(:due_date).present?
    invoice.date ||= Time.at(stripe_invoice.created).to_datetime if stripe_invoice.try(:created).present?

    if !invoice.save
      context.fail!(message: "Couldn't save invoice #{number} with new status: #{new_status}")
    end

    if invoice.paid?
      result = Billing::Invoices::AddCreditsToSubscribable.call(
        invoice: invoice
      )

      if !result.success?
        context.fail!(message: result.message)
      end
    end
  end
end