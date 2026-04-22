
module Refundable
  class RefundableInvoice < SimpleDelegator
    def cancel
      return true if refunded?

      stripe_refund = if stripe_payment_intent_id.present?
        # New PaymentIntent-backed invoices (reservation hold/capture).
        refund_payment_intent
      else
        # Legacy Stripe Invoice-backed invoices.
        self.location.create_stripe_refund(self)
      end

      refunds.create(
        amount: amount_due,
        stripe_refund_id: stripe_refund.id
      )

      update(
        status: 'refunded',
        refunded_at: Time.current,
        refund_amount_in_cents: amount_due,
      )
    end

    private

    def refund_payment_intent
      Stripe::Refund.create(
        { payment_intent: stripe_payment_intent_id, amount: amount_due },
        {
          api_key: location&.stripe_secret_key || operator&.stripe_secret_key,
          stripe_account: location&.stripe_user_id || operator&.stripe_user_id,
        }
      )
    end
  end
end
