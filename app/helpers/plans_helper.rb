# typed: false
module PlansHelper
  def dollar_amount(cents)
    new_amount = cents.to_f / 100.0
    number_to_currency(new_amount)
  end

  def plan_params
    p = params.require(:plan).permit(:name, :plan_type, :interval, :amount_in_cents, :visible, :available, :always_allow_building_access, :has_day_limit, :day_limit)
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    p
  end
end