class Billing::Payment::SetToOutOfBand
  include Interactor

  delegate :user, :location, to: :context

  def call
    user.subscriptions_billable.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "send_invoice"
      stripe_sub.days_until_due = 30
      stripe_sub.save
    end

    user.update_card_added_for_location(location, false)
    if !user.update(card_added: false, out_of_band: true, bill_to_organization: false)
      context.fail!(message: "Unable to update payment method: #{user.errors.full_messages.join(', ')}")
    end
  end
end
