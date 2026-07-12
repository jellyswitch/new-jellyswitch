module Notifiable
  # Member-facing push on a failed invoice payment ("failed-card save") — the
  # push counterpart of UserMailer.payment_failed_email. Dispatched from the
  # invoice.payment_failed webhook on every Stripe dunning attempt (matching the
  # email's cadence), so the member gets a phone nudge to fix their card before
  # Stripe cancels the subscription. Wraps the Invoice.
  class PaymentFailed < Notifiable::Default
    private

    # The webhook branch already posts the admin feed item — don't duplicate it.
    def create_feed_item
    end

    # Mobile routes payment_failed → the member's Payment Method (card update)
    # screen; older builds without the route fall back to opening the app.
    # Org-billed invoices charge the ORGANIZATION's Stripe customer, which that
    # screen cannot fix (it updates the owner's personal card) — send a type
    # with no mobile target so the tap just opens the app instead of mis-routing.
    def deep_link_data
      type = org_billed? ? "org_payment_failed" : "payment_failed"
      { type: type, resource_id: id, path: "/billing" }
    end

    # Skip if the invoice was settled/voided between the webhook and this job
    # running — a "payment failed" push after they've paid would be false.
    def should_send_notification?
      open?
    end

    def message
      amount = format("$%.2f", amount_due.to_i / 100.0)
      if org_billed?
        "Your organization's #{amount} payment failed — please update its payment method."
      else
        "Your #{amount} payment failed — please update your card."
      end
    end

    # Same resolution as the email + admin feed item: the billable member, or
    # the owner when the invoice bills an Organization. ::User — inside this
    # module a bare User resolves to Notifiable::User, the adapter.
    def recipients
      [org_billed? ? billable.try(:owner) : billable].compact
    end

    def org_billed?
      !billable.is_a?(::User)
    end
  end
end
