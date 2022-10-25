
class Billable::DayPass < SimpleDelegator
  attr_accessor :billable, :day_pass

  def initialize(day_pass)
    @day_pass = day_pass
  end

  def billable
    if day_pass.user.bill_to_organization? && day_pass.user.member_of_organization? && day_pass.user.organization.present?
      OrganizationBillDecider.new(organization: day_pass.user.organization).billable
    else
      day_pass.user
    end
  end
end