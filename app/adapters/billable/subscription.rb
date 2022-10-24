
class Billable::Subscription < SimpleDelegator
  attr_accessor :billable, :subscription

  def initialize(subscription)
    @subscription = subscription
  end

  def billable
    case @subscription.subscribable_type
    when "User"
      user
    when "Organization"
      # This is probably an office lease
      if @subscription.subscribable.billing_contact.present?
        @subscription.subscribable.billing_contact
      else
        @subscription.subscribable
      end
    end
  end

  private

  def user
    if subscription.subscribable.member_of_organization?
      if subscription.subscribable.bill_to_organization?
        if subscription.subscribable.organization.billing_contact.present?
          subscription.subscribable.organization.billing_contact
        else
          subscription.subscribable.organization
        end
      else
        subscription.subscribable
      end
    else
      subscription.subscribable
    end
  end
end