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
end