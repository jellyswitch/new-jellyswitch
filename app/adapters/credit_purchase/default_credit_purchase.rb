class CreditPurchase::DefaultCreditPurchase < SimpleDelegator
  attr_accessor :user, :location

  def initialize(user, location)
    @user = user
  end

  def invoice_args
    {
      customer: user.stripe_customer_id_for_location(location),
      auto_advance: true
    }
  end
end
