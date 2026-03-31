
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
          # Stripe call returned false — try marking locally only
          invoice.update(status: 'paid')
          Rails.logger.warn("MarkInvoiceAsPaid: Stripe call failed for invoice #{invoice.id}, marked paid locally only")
        end
      rescue Stripe::InvalidRequestError => e
        if e.message.include?('already paid')
          invoice.update(status: 'paid')
        elsif e.message.include?('void') || e.message.include?('uncollectible')
          context.fail!(message: "Cannot mark as paid: this invoice has been voided or marked uncollectible in Stripe.")
        else
          context.fail!(message: "Stripe error: #{e.message}")
        end
      end
    else
      # No location — mark paid locally without Stripe
      invoice.update(status: 'paid')
    end
  end
end
