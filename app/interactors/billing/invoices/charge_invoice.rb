
class Billing::Invoices::ChargeInvoice
  include Interactor

  delegate :invoice, :operator, to: :context

  def call
    # Use the invoice's location for Stripe credentials since the invoice
    # was created on the location's connected account
    stripe_account = invoice.location || operator
    if stripe_account.charge_invoice(invoice)
      invoice.update(status: 'paid')
    else
      context.fail!(message: 'Failed to mark invoice as paid.')
    end
  end
end