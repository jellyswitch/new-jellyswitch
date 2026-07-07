# Syncs a Stripe refund back onto the local Invoice. Without this, a refund
# issued directly in the Stripe Dashboard never reaches us: the Invoice stays
# `paid`/refundable while Stripe shows it refunded, and the next in-app "Refund"
# click hits `charge_already_refunded` (Honeybadger fault 132040149).
#
# Wired to three event types, all of which a single refund can fire:
#   * charge.refunded       — object is the Charge (carries invoice + payment_intent
#                             + amount_refunded inline; the workhorse)
#   * refund.created        — object is the Refund (carries the exact refund id)
#   * charge.refund.updated — object is the Refund (status changes)
#
# Reconciliation is idempotent (see RefundableInvoice#reconcile_refund!), so the
# duplicate events are harmless.
class Webhooks::ChargeRefunded
  include Interactor

  delegate :event, to: :context

  def call
    info = extract(event.data.object)
    invoice = find_invoice(info)

    # No local invoice for this charge (a charge we don't track, or the wrong
    # environment). Acknowledge so Stripe stops retrying.
    return if invoice.nil?

    Refundable::RefundableInvoice.new(invoice).reconcile_refund!(
      amount_cents: info[:amount_cents].to_i,
      stripe_refund_id: info[:stripe_refund_id],
    )

    # Stripe-Dashboard refunds arrive only here, so this is where a day pass
    # refunded outside the app gets rescinded. Best-effort: a rescind failure
    # must not fail the (idempotent, already-reconciled) webhook.
    rescind_day_passes(invoice)
  rescue => e
    context.fail!(message: "#{event.type} reconcile failed: #{e.class}: #{e.message}")
  end

  private

  def rescind_day_passes(invoice)
    Billing::DayPasses::RescindForInvoice.call(invoice: invoice)
  rescue => e
    Rails.logger.warn(
      "[ChargeRefunded] rescinding day pass(es) failed for invoice #{invoice.id}: #{e.class}: #{e.message}",
    )
    Honeybadger.notify(e) if defined?(Honeybadger)
  end

  # Normalize a Charge (charge.refunded) or a Refund (refund.created /
  # charge.refund.updated) into the fields we need to match + reconcile.
  def extract(object)
    case object.try(:object)
    when "charge"
      {
        stripe_invoice_id: object.try(:invoice),
        stripe_payment_intent_id: object.try(:payment_intent),
        charge_id: object.try(:id),
        amount_cents: object.try(:amount_refunded),
        stripe_refund_id: latest_refund_id(object),
      }
    when "refund"
      {
        stripe_invoice_id: nil,
        stripe_payment_intent_id: object.try(:payment_intent),
        charge_id: object.try(:charge),
        amount_cents: object.try(:amount),
        stripe_refund_id: object.try(:id),
      }
    else
      {}
    end
  end

  # The Charge's `refunds` list isn't expanded on every API version, so this may
  # be nil for charge.refunded — that's fine, refund.created backfills the id.
  def latest_refund_id(charge)
    charge.try(:refunds)&.try(:data)&.first&.try(:id)
  end

  # Legacy invoices are Stripe-Invoice-backed (invoice.stripe_invoice_id ==
  # charge.invoice); newer ones are PaymentIntent-backed
  # (invoice.stripe_payment_intent_id == charge.payment_intent). Refund-object
  # events don't carry the Stripe invoice id, so for those we fall back to
  # retrieving the charge to discover invoice/PI.
  def find_invoice(info)
    if info[:stripe_invoice_id].present?
      invoice = Invoice.find_by(stripe_invoice_id: info[:stripe_invoice_id])
      return invoice if invoice
    end

    if info[:stripe_payment_intent_id].present?
      invoice = Invoice.find_by(stripe_payment_intent_id: info[:stripe_payment_intent_id])
      return invoice if invoice
    end

    find_via_charge(info[:charge_id])
  end

  # Last resort for a Refund object that carried neither an invoice id nor a
  # payment_intent (legacy charge): retrieve the charge on the connected account
  # and match on its invoice / payment_intent.
  def find_via_charge(charge_id)
    return nil if charge_id.blank?

    charge = retrieve_charge(charge_id)
    return nil if charge.nil?

    if charge.try(:invoice).present?
      invoice = Invoice.find_by(stripe_invoice_id: charge.invoice)
      return invoice if invoice
    end
    if charge.try(:payment_intent).present?
      return Invoice.find_by(stripe_payment_intent_id: charge.payment_intent)
    end
    nil
  end

  def retrieve_charge(charge_id)
    operator = Operator.find_by(stripe_user_id: event.try(:account))
    return nil if operator.nil? || operator.stripe_secret_key.blank?

    Stripe::Charge.retrieve(
      charge_id,
      api_key: operator.stripe_secret_key,
      stripe_account: operator.stripe_user_id,
    )
  rescue Stripe::StripeError
    nil
  end
end
