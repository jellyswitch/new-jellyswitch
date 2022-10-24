
class Billable::Checkin < SimpleDelegator
  attr_accessor :billable, :checkin

  def initialize(checkin)
    @checkin = checkin
  end

  def billable
    if checkin.user.bill_to_organization? && checkin.user.member_of_organization? && checkin.user.organization.present?
      OrganizationBillDecider.new(checkin.user.organization).billable
    else
      checkin.user
    end
  end
end