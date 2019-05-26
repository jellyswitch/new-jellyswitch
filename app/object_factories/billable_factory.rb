class BillableFactory
  attr_accessor :invoiceable

  def initialize(invoiceable)
    # invoiceable is a subscription, day pass, or checkin
    @invoiceable = invoiceable
  end

  def billable
    case invoiceable.class.name
    when "Subscription"
      Billable::Subscription.new(invoiceable).billable
    when "Checkin"
      raise "Not Implemented"
    when "DayPass"
      raise "Not Implemented"
    end
  end
end