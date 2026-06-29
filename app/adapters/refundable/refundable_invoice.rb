
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

    # Bring the local Invoice in line with a refund that already happened on
    # Stripe — almost always a refund issued directly in the Stripe Dashboard,
    # synced here by the `charge.refunded` webhook (Webhooks::ChargeRefunded).
    # Idempotent: a single Dashboard refund fires 2-3 events (charge.refunded,
    # refund.created, charge.refund.updated) and members may also click "Refund"
    # locally, so this must never double-record or keep bumping refunded_at.
    #
    #   amount_cents      - the refunded amount (Stripe amount_refunded / refund.amount)
    #   stripe_refund_id  - the Stripe Refund id (re_...), when the event carries one
    def reconcile_refund!(amount_cents:, stripe_refund_id: nil)
      # Already recorded this exact Stripe refund — nothing to do.
      return true if stripe_refund_id.present? && refunds.exists?(stripe_refund_id: stripe_refund_id)

      if stripe_refund_id.present? && (placeholder = refunds.where(stripe_refund_id: nil).first)
        # An earlier amount-only reconcile (the #cancel already-refunded path, or
        # a charge.refunded with no inline refund id) left a row without an id;
        # stamp the real id on it rather than creating a duplicate.
        placeholder.update(stripe_refund_id: stripe_refund_id, amount: amount_cents)
      elsif refunds.empty?
        refunds.create(amount: amount_cents, stripe_refund_id: stripe_refund_id)
      end

      update(
        status: 'refunded',
        refunded_at: refunded_at || Time.current,
        refund_amount_in_cents: refund_amount_in_cents.presence || amount_cents,
      )
      true
    end

    private

    def already_refunded_error?(e)
      e.code == 'charge_already_refunded' || e.message.to_s.include?('already been refunded')
    end

    # Bring local state in line with Stripe's already-refunded charge. We don't
    # have the out-of-band refund's Stripe id from the InvalidRequestError, so we
    # record the amount our retention policy would have refunded; the
    # `charge.refunded` webhook later backfills the exact id/amount.
    def reconcile_already_refunded!(refund_cents)
      reconcile_refund!(amount_cents: refund_cents)
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
