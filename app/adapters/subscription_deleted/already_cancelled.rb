class SubscriptionDeleted::AlreadyCancelled < SimpleDelegator
  attr_accessor :subscription

  def initialize(subscription)
    @subscription = subscription
  end

  def perform
    if subscription.active?
      @result = subscription.update(active: false)
    end
    self
  end

  def success?
    @result
  end

  def message
    "AlreadyCancelled::Message for #{subscription.stripe_subscription_id}"
  end
end