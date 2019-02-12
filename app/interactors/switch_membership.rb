class SwitchMembership
  include Interactor

  def call
    old_subscription = context.old_subscription
    new_subscription = context.new_subscription

    new_subscription.user = old_subscription.user # in case this is an admin

    result = CreateSubscription.call(
      subscription: new_subscription,
      user: old_subscription.user,
      token: nil
    )

    if result.success?
      result = CancelSubscription.call(subscription: old_subscription)
      if !result.success?
        context.fail!(message: "Unable to deactivate existing membership")
      end
    else
      context.fail!(message: result.message)
    end
  end
end