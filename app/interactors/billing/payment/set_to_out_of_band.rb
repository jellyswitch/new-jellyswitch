class Billing::Payment::SetToOutOfBand
  include Interactor

  delegate :user, to: :context

  def call
    user.subscriptions_billable.active.each do |subscription|
      stripe_subscription = subscription.stripe_subscription
      stripe_subscription.billing = "send_invoice"
      stripe_subscription.days_until_due = 30
      stripe_subscription.save
    end

    if !user.update(card_added: false, out_of_band: true, bill_to_organization: false)
      context.fail!(message: "An error occurred.")
    end
  end
end
