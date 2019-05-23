module DayPassable
  class DefaultDayPass < SimpleDelegator
    attr_accessor :day_pass, :user

    def initialize(day_pass, user)
      @day_pass = day_pass
      @user = user
    end

    def invoice_args
      {
        customer: user.stripe_customer_id,
        auto_advance: true
      }
    end
  end
end