
module Refundable
  class RefundableInvoice < SimpleDelegator
    def cancel
      return true if refunded?

      refund_cents = refundable_amount_in_cents
      if refund_cents <= 0
        # Operator's retention policy keeps the entire amount — record
        # the refund as $0 so the invoice marks refunded but no money
        # leaves the platform. Caller can still see refund_amount=0.
        return update(status: 'refunded', refunded_at: Time.current, refund_amount_in_cents: 0)
      end

      stripe_refund = if stripe_payment_intent_id.present?
        # New PaymentIntent-backed invoices (reservation hold/capture).
        refund_payment_intent(refund_cents)
      else
        # Legacy Stripe Invoice-backed invoices.
        self.location.create_stripe_refund(self, nil, amount: refund_cents)
      end

      refunds.create(
        amount: refund_cents,
        stripe_refund_id: stripe_refund.id,
      )

      update(
        status: 'refunded',
        refunded_at: Time.current,
        refund_amount_in_cents: refund_cents,
      )
    rescue Stripe::InvalidRequestError => e
      # The charge was already fully refunded out-of-band — almost always a
      # refund issued directly in the Stripe Dashboard, which we don't yet sync
      # via webhook, so our local `refunded?` guard (refunds.length > 0) still
      # read false. The money has already been returned, so reconcile our records
      # to match Stripe and report success rather than erroring on the operator.
      # Same philosophy as StripeUtils#mark_invoice_paid's "already paid" path.
      raise unless already_refunded_error?(e)
      reconcile_already_refunded!(refund_cents)
      true
    end

    private

    def already_refunded_error?(e)
      e.code == 'charge_already_refunded' || e.message.to_s.include?('already been refunded')
    end

    # Bring local state in line with Stripe's already-refunded charge. We don't
    # have the out-of-band refund's Stripe id without an extra lookup, so we
    # record the amount our retention policy would have refunded; a
    # `charge.refunded` webhook (recommended) would capture the exact id/amount.
    def reconcile_already_refunded!(refund_cents)
      refunds.create(amount: refund_cents) if refunds.empty?
      update(
        status: 'refunded',
        refunded_at: Time.current,
        refund_amount_in_cents: refund_cents,
      )
    end

    # Honors the operator's processing-fee retention policy. Stripe
    # keeps its % fee on the original charge whether or not we refund,
    # so operators typically configure 3% (or whatever their effective
    # processor rate is) to avoid eating that cost on every refund.
    def refundable_amount_in_cents
      pct = (operator&.try(:refund_fee_percent) || 0).to_i
      return amount_due.to_i if pct <= 0
      pct = 100 if pct > 100
      retained = (amount_due.to_i * pct / 100.0).round
      [amount_due.to_i - retained, 0].max
    end

    def refund_payment_intent(amount_in_cents)
      Stripe::Refund.create(
        { payment_intent: stripe_payment_intent_id, amount: amount_in_cents },
        {
          api_key: location&.stripe_secret_key || operator&.stripe_secret_key,
          stripe_account: location&.stripe_user_id || operator&.stripe_user_id,
        }
      )
    end
  end
end
