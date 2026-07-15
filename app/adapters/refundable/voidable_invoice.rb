
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
    end
  end
end
