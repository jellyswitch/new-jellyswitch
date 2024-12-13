class Billing::Payment::SetToCreditCard
  include Interactor

  delegate :user, :location, to: :context

  def call
    if (payment_profile = user.payment_profile_for_location(location))
      user.subscriptions_billable.active.each do |subscription|
        stripe_subscription = subscription.stripe_subscription
        stripe_subscription.billing = "charge_automatically"
        stripe_subscription.save
      end

      payment_profile.update card_added: true
      if !user.update(out_of_band: false, bill_to_organization: false, card_added: true)
        context.fail!(message: "An error occurred.")
      end
    else
      context.fail!(message: "User has no card on file.")
    end
  end
end
