
class Billable::Checkin < SimpleDelegator
  attr_accessor :billable, :checkin

  def initialize(checkin)
    @checkin = checkin
  end

  def billable
    if checkin.user.member_of_organization?
      if checkin.user.bill_to_organization? && checkin.user.organization.present?
        OrganizationBillDecider.new(organization: checkin.user.organization).billable
      else
        checkin.user
      end
    else
      checkin.user
    end
  end
end