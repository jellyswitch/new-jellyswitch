class Billing::Subscription::SaveSubscription
  include Interactor

  delegate :subscription, :user, :start_day, to: :context

  def call
    unless user.has_billing? || user.out_of_band?
      context.fail!(message: "Can't add a subscription for someone with no billing info on file.")
    end

    if subscription.save
      context.subscription = subscription
    else
      context.fail!(message: "There was a problem creating this subscription.")
    end
  end
end
