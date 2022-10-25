
class Billable::DayPass < Billable::Default
  attr_accessor :billable, :day_pass

  def initialize(day_pass)
    @day_pass = day_pass
  end

  def billable
    find_billable(billable: day_pass)
  end
end