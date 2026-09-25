
class Billing::Invoices::ChargeInvoice
  include Interactor

  delegate :invoice, :operator, to: :context

  def call
    # Use the invoice's location for Stripe credentials since the invoice
    # was created on the location's connected account
    stripe_account = invoice.location || operator
    if stripe_account.charge_invoice(invoice)
      invoice.update(status: 'paid')
      send_receipt
    else
      context.fail!(message: 'Failed to mark invoice as paid.')
    end
  end

  private

  # Every successful charge emails the customer a receipt — a durable,
  # purchase-specific confirmation. The product "onboarding" email is a
  # welcome/orientation message that only makes sense once; a repeat buyer
  # (second day pass for the same day, another bundle) otherwise got nothing
  # they could recognise as confirmation of the new charge. Best-effort:
  # a mail failure must never fail the charge.
  def send_receipt
    return unless invoice.paid?
    return if invoice.amount_due.to_i <= 0
    return if invoice.billable&.email.blank?

    UserMailer.invoice_receipt_email(invoice).deliver_later
  rescue StandardError => e
    Rails.logger.error("ChargeInvoice receipt failed for invoice #{invoice.id}: #{e.class}: #{e.message}")
    Honeybadger.notify(e) if defined?(Honeybadger)
  end
end
