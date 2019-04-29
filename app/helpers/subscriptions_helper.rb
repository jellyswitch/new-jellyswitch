module SubscriptionsHelper
  def find_subscription(key=:id)
    @subscription = Subscription.find(params[key])
  end
end