class SubscriptionDeletedFactory
  def self.for(subscription)
    if subscription.active?
      if subscription.office_leases.count > 0
        SubscriptionDeleted::OfficeLease
      else
        SubscriptionDeleted::Membership
      end
    else
      SubscriptionDeleted::AlreadyCancelled
    end.new(subscription)
  end
end