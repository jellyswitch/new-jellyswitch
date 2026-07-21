
module Refundable
  class VoidableInvoice < SimpleDelegator
    def cancel
      stripe_invoice = self.location.retrieve_stripe_invoice(self)

      case stripe_invoice.status
      when 'draft'
        stripe_invoice.delete
      when 'open'
        stripe_invoice.void_invoice
      when 'paid'
        # We think this invoice is still open (voidable? is a LOCAL check), but
        # Stripe already collected it — webhook lag, or a payment taken in the
        # Stripe Dashboard. Voiding it locally would drop real, collected revenue
        # from the books with no refund issued. Refuse; the money must go out
        # through the refund path once local status catches up to Stripe.
        raise "Cannot void invoice #{id}: Stripe shows it as paid. Issue a refund instead."
      end

      update(status: 'void')
    rescue Stripe::InvalidRequestError => e
      # The invoice doesn't exist on the currently connected Stripe account —
      # the operator reconnected to a different account, orphaning invoices
      # created before the switch (Tahoe Longhouse, 2026-07-17). There is
      # nothing to void on Stripe's side, but local bookkeeping must still
      # resolve or the invoice stays open forever. Any other Stripe failure
      # (auth, permissions, a void Stripe refuses) re-raises and fails loudly.
      raise unless missing_invoice_error?(e)
      update(status: 'void')
    end

    private

    def missing_invoice_error?(e)
      e.message.to_s.include?('No such invoice')
    end
  end
end
