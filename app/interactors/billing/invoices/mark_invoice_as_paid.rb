
class Billing::Invoices::MarkInvoiceAsPaid
  include Interactor

  delegate :invoice, :operator, to: :context

  def call
    if invoice.location
      if invoice.location.mark_invoice_paid(invoice, paid_out_of_band: true)
        invoice.update(status: 'paid')

        result = Billing::Invoices::AddCreditsToSubscribable.call(
          invoice: invoice
        )

        if !result.success?
          context.fail!(message: result.message)
        end
      else
        context.fail!(message: 'Failed to mark invoice as paid.')
      end
    else
      context.fail!(message: 'Invoice location is missing')
    end
  end
end
