class CancelSubscriptionJob < ApplicationJob
  queue_as :default

  def perform(subscription:)
    CancelSubscription.call(
      subscription: subscription
    )
  end
end
