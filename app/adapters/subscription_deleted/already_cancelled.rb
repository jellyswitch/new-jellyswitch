class SubscriptionDeleted::AlreadyCancelled < SimpleDelegator
  attr_accessor :subscription

  def initialize(subscription)
    @subscription = subscription
  end

  def perform
    self
  end

  def success?
    true # to hack the interactor pattern return value
  end
end