class BillableFactory
   def self.for(invoiceable)
    case invoiceable.class.name
    when "Subscription"
      Billable::Subscription
    when "Checkin"
      raise "Not Implemented"
    when "DayPass"
      raise "Not Implemented"
    else
      raise "Cannot determine billable for #{invoiceable.class.name}"
    end.new(invoiceable)
  end
end