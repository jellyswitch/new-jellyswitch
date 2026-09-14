class Billing::Invoices::AddCreditsToSubscribable
  include Interactor

  delegate :invoice, to: :context

  def call
    # Callers that already hold the Stripe invoice (the webhook, CreateInvoice)
    # pass it through so we don't re-fetch it. Otherwise Invoice#stripe_invoice
    # retrieves it — and returns nil when the invoice has no location (legacy /
    # webhook rows) or Stripe can't find it, so bail instead of crashing.
    stripe_invoice = context.stripe_invoice || invoice.stripe_invoice
    return if stripe_invoice.nil?

    lines = stripe_invoice.try(:lines)
    return if lines.nil? || lines.count == 0

    first_line = lines.first
    return unless first_line.respond_to?(:subscription) && first_line.subscription.present?

    subscription = invoice.operator.subscriptions.find_by(stripe_subscription_id: first_line.subscription)
    if subscription
      credits(subscription)
      childcare_reservations(subscription)
    end
  end

  def credits(subscription)
    if invoice.location&.credits_enabled?
      if subscription.plan.credits > 0
        subscription.subscribable.update(credit_balance: subscription.plan.credits)
      end
    end
  end

  def childcare_reservations(subscription)
    if invoice.location&.childcare_enabled?
      if subscription.plan.childcare_reservations > 0
        subscription.subscribable.update(childcare_reservation_balance: subscription.plan.childcare_reservations)
      end
    end
  end
end
