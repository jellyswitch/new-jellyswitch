class Billable::Default
  protected

  def find_billable(billable:)
    if billable.subscribable.member_of_organization?
      if billable.subscribable.bill_to_organization? && billable.subscribable.organization.present?
        OrganizationBillDecider.new(organization: billable.subscribable.organization).billable
      else
        billable.subscribable
      end
    else
      billable.subscribable
    end
  end
end