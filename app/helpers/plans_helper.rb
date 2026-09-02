
module PlansHelper
  def dollar_amount(cents)
    cents.to_f / 100.0
  end

  def plan_params
    p = params.require(:plan).permit(:name, :plan_type, :interval, :amount_in_cents,
      :visible, :available, :building_access_level, :has_day_limit, :day_limit,
      :credits, :commitment_interval, :description, :childcare_reservations, :plan_category_id,
      :included_meeting_room_minutes, :overage_rate_in_cents,
      :featured, :display_order, :features_text, :features_default, location_ids: [])
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    p[:location_id] = current_location.id if current_location
    convert_meeting_room_params!(p)
    if p.key?(:features_text)
      lines = p.delete(:features_text).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      defaults = p.delete(:features_default).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      # The form prefills the automatic lines; saving them untouched keeps the
      # product on automatic, so later config changes still flow to the website.
      p[:features] = lines == defaults ? [] : lines
    end
    p
  end

  def convert_meeting_room_params!(p)
    if p[:included_meeting_room_minutes].present?
      p[:included_meeting_room_minutes] = (p[:included_meeting_room_minutes].to_f * 60).to_i
    else
      p[:included_meeting_room_minutes] = nil
    end
    if p[:overage_rate_in_cents].present?
      p[:overage_rate_in_cents] = (p[:overage_rate_in_cents].to_f * 100).to_i
    else
      p[:overage_rate_in_cents] = 0
    end
  end

  def plans_for_categorization
    current_location.plans.uncategorized.available.individual.visible.order(:name, :amount_in_cents).all
  end
end