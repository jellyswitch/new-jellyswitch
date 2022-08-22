class CancelSubscriptionJob < ApplicationJob
  queue_as :default

  def perform(subsciption:)
    CancelSubscription.call(
      subscription: subsciption
    )
  end
end
