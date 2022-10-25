
class Billable::Checkin < Billable::Default
  attr_accessor :billable, :checkin

  def initialize(checkin)
    @checkin = checkin
  end

  def billable
    find_billable(billable: checkin)
  end
end