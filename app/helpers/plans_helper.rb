module PlansHelper
  def dollar_amount(cents)
    new_amount = cents.to_f / 100.0
    number_to_currency(new_amount)
  end
end