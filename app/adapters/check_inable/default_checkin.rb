# TODO: this doesn't seem used
module DayPassable
  class CheckInable::DefaultCheckin < SimpleDelegator
    attr_accessor :checkin

    def initialize(checkin)
      @checkin = checkin
    end

    def invoice_args
      {
        customer: checkin.billable.stripe_customer_id_for_location(checkin.location),
        auto_advance: true
      }
    end
  end
end