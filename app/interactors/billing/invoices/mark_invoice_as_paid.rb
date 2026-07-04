
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

    # Only talk to Stripe when there's a Stripe invoice to reconcile —
    # locally-created invoices (e.g. reservation captures) have no
    # stripe_invoice_id and retrieving nil would raise.
    if invoice.location && invoice.stripe_invoice_id.present?
      begin
        if invoice.location.mark_invoice_paid(invoice, paid_out_of_band: true)
          mark_paid_locally

          result = Billing::Invoices::AddCreditsToSubscribable.call(
            invoice: invoice
          )

          if !result.success?
            context.fail!(message: result.message)
          end
        else
          # Stripe call returned false — try marking locally only
          mark_paid_locally
          Rails.logger.warn("MarkInvoiceAsPaid: Stripe call failed for invoice #{invoice.id}, marked paid locally only")
        end
      rescue Stripe::InvalidRequestError => e
        if e.message.include?('already paid')
          mark_paid_locally
        elsif e.message.include?('void') || e.message.include?('uncollectible')
          context.fail!(message: "Cannot mark as paid: this invoice has been voided or marked uncollectible in Stripe.")
        else
          context.fail!(message: "Stripe error: #{e.message}")
        end
      end
    else
      # No Stripe invoice — mark paid locally only
      mark_paid_locally
    end
  end

  private

  # Recording receipt of an out-of-band payment (check/ACH). Stamp the
  # fields revenue reads: without a date the invoice is invisible to every
  # revenue window, and amount_paid otherwise stays 0 forever.
  def mark_paid_locally
    invoice.update(
      status: 'paid',
      amount_paid: invoice.amount_due,
      date: invoice.date || Time.current,
    )
  end
end
