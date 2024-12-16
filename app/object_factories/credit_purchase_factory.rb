class CreditPurchaseFactory
  def self.for(user, location)
    if user.out_of_band?
      CreditPurchase::OutOfBand
    else
      CreditPurchase::InBand
    end.new(user, location)
  end
end