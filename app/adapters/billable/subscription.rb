
class Billable::Subscription < SimpleDelegator
  attr_accessor :billable, :subscription

  def initialize(subscription)
    @subscription = subscription
  end

  def billable
    case @subscription.subscribable_type
    when "User"
      if subscription.subscribable.member_of_organization?
        if subscription.subscribable.bill_to_organization? && subscription.subscribable.organization.present?
          OrganizationBillDecider.new(organization: subscription.subscribable.organization).billable
        else
          subscription.subscribable
        end
      else
        subscription.subscribable
      end
    when "Organization"
      # This is probably an office lease
      OrganizationBillDecider.new(organization: @subscription.subscribable).billable
    end
  end

  private


end