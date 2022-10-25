
class Billable::Subscription < Billable::Default
  def initialize(subscription)
    @subscription = subscription
  end

  def billable
    case @subscription.subscribable_type
    when "User"
      find_billable(billable: @subscription)
    when "Organization"
      # This is probably an office lease
      OrganizationBillDecider.new(organization: @subscription.subscribable).billable
    end
  end
end