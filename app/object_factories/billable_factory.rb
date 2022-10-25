
class BillableFactory
   def self.for(invoiceable)
    case invoiceable.class.name
    when "Subscription"
      case invoiceable.subscribable_type
      when "User"
        Billable::Default
      when "Organization"
        Billable::Subscription::Organization
      end
    when "Checkin"
      Billable::Default
    when "DayPass"
      Billable::Default
    else
      raise "Cannot determine billable for #{invoiceable.class.name}"
    end.new(billable: invoiceable)
  end
end