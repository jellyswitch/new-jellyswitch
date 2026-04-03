class Billing::Payment::SetToCreditCard
  include Interactor

  delegate :user, :location, to: :context

  def call
    if (payment_profile = user.payment_profile_for_location(location))
      user.subscriptions_billable.active.each do |subscription|
        stripe_sub = subscription.stripe_subscription
        next unless stripe_sub
        stripe_sub.billing = "charge_automatically"
        stripe_sub.save
      end

      payment_profile.update card_added: true
      user.assign_attributes(out_of_band: false, bill_to_organization: false, card_added: true)
      if !user.save(context: :payment_method)
        context.fail!(message: "Unable to update payment method: #{user.errors.full_messages.join(', ')}")
      end
    else
      context.fail!(message: "User has no card on file.")
    end
  end
end
