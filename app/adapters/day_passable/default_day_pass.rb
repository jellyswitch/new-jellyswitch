
module DayPassable
  class DefaultDayPass < SimpleDelegator
    attr_accessor :day_pass

    def initialize(day_pass)
      @day_pass = day_pass
    end

    def invoice_args
      {
        customer: day_pass.billable.stripe_customer_id_for_location(day_pass.location),
        # auto_advance: false so the invoice is finalized + paid synchronously
        # by ChargeDayPassInvoice. The previous true setting deferred the charge
        # by ~1 hour, so members who didn't see an immediate confirmation
        # retried — generating duplicate invoices and multiple decline attempts
        # against their card.
        auto_advance: false
      }
    end
  end
end