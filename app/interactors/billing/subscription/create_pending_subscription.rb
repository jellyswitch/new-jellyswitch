class Billing::Subscription::CreatePendingSubscription
  include Interactor

  delegate :subscription, :user, :start_day, to: :context

  def call
    if !user.out_of_band? && !user.card_added?
      # create a pending subscription instead
      subscription.pending = true
      subscription.active = false
    end

    if subscription.save
      context.subscription = subscription
    else
      context.fail!(message: "There was a problem creating this subscription.")
    end
  end
end