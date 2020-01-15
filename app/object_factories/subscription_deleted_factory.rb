class SubscriptionDeletedFactory
  def self.for(subscription)
    if subscription.active?
      if subscription.stripe_subscription.status == "cancelled"
        SubscriptionDeleted::AlreadyCancelled
      else
        if subscription.office_leases.count > 0
          SubscriptionDeleted::OfficeLease
        else
          SubscriptionDeleted::Membership
        end
      end
    else
      SubscriptionDeleted::AlreadyCancelled
    end.new(subscription)
  end
end