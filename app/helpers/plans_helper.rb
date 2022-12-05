
module PlansHelper
  def dollar_amount(cents)
    cents.to_f / 100.0
  end

  def plan_params
    p = params.require(:plan).permit(:name, :plan_type, :interval, :amount_in_cents, 
      :visible, :available, :always_allow_building_access, :has_day_limit, :day_limit, 
      :credits, :commitment_interval, :description, :childcare_reservations, :plan_category_id, location_ids: [])
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    p
  end

  def plans_for_categorization
    current_tenant.plans.uncategorized.available.individual.visible.order(:name, :amount_in_cents).all
  end
end