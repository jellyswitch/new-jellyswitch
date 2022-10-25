class Billable::Subscription::OfficeLease < Billable::Default
  def find_billable(billable:)
    OrganizationBillDecider.new(organization: billable.subscribable).billable
  end
end