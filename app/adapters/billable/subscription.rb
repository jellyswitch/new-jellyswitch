
class Billable::Subscription < Billable::Default
  private

  def find_billable(billable:)
    case billable.subscribable_type
    when "User"
      super(billable: billable)
    when "Organization"
      # This is an office lease
      OrganizationBillDecider.new(organization: billable.subscribable).billable
    end
  end
end