class Billable::Subscription::Organization < Billable::Default
  def find_billable(billable:)
    if billable.billable.has_billing_contact?
      billable.billable.billing_contact
    else
      billable.billable
    end
  end
end