class Billing::Invoices::AddCreditsToSubscribable
  include Interactor

  delegate :invoice, :operator, to: :context

  def call
    stripe_invoice = invoice.stripe_invoice
    if stripe_invoice.lines.count > 0
      if stripe_invoice.lines.first.respond_to? :subscription
        subscription = operator.subscriptions.find_by(stripe_subscription_id: invoice.stripe_invoice.lines.first.subscription)
        if subscription
          if subscription.plan.credits > 0
            subscription.subscribable.update(credit_balance: subscription.plan.credits)
          end
        end
      end
    end
  end
end