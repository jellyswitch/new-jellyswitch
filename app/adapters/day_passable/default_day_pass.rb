
module DayPassable
  class DefaultDayPass < SimpleDelegator
    attr_accessor :day_pass

    def initialize(day_pass)
      @day_pass = day_pass
    end

    def invoice_args
      {
        customer: day_pass.billable.stripe_customer_id_for_location(day_pass.location),
        auto_advance: true
      }
    end
  end
end