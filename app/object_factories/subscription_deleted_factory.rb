class SubscriptionDeletedFactory
  def self.for(subscription)
    sub = subscription.stripe_subscription
    if subscription.active? == false && sub&.status == "canceled"
      SubscriptionDeleted::AlreadyCancelled
    else
      if subscription.office_leases.count > 0
        SubscriptionDeleted::OfficeLease
      else
        SubscriptionDeleted::Membership
      end
    end.new(subscription)
  end
end
