
class Billing::Invoices::MarkInvoiceAsPaid
  include Interactor

  delegate :invoice, :operator, to: :context

  def call
    # Reload to get the latest status and avoid race conditions
    invoice.reload

    if invoice.paid?
      context.fail!(message: 'Invoice is already paid.')
      return
    end

    if invoice.location
      begin
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
      rescue Stripe::InvalidRequestError => e
        if e.message.include?('already paid')
          # Invoice was paid between our check and the Stripe call (race condition)
          invoice.update(status: 'paid')
        else
          raise
        end
      end
    else
      context.fail!(message: 'Invoice location is missing')
    end
  end
end
