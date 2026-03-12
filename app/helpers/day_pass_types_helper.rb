
module DayPassTypesHelper
  def day_pass_type_options(day_pass_types)
    day_pass_types.map do |day_pass_type|
      [
        "#{day_pass_type.name} (#{number_to_currency(day_pass_type.amount_in_cents.to_f / 100.00)})",
        day_pass_type.id,
      ]
    end
  end

  def day_pass_type_params
    p = params.require(:day_pass_type).permit(:name, :amount_in_cents, :available, :visible, :always_allow_building_access, :code, :description, :included_meeting_room_minutes, :overage_rate_in_cents)
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    # Convert hours input to minutes
    if p[:included_meeting_room_minutes].present?
      p[:included_meeting_room_minutes] = (p[:included_meeting_room_minutes].to_f * 60).to_i
    else
      p[:included_meeting_room_minutes] = nil
    end
    # Convert dollars to cents for overage rate
    if p[:overage_rate_in_cents].present?
      p[:overage_rate_in_cents] = Money.from_amount(p[:overage_rate_in_cents].to_f, "USD").cents
    end
    p[:location_id] = current_location.id if current_location
    p
  end


  def day_pass_type_update_params
    p = params.require(:day_pass_type).permit(:code, :description, :included_meeting_room_minutes, :overage_rate_in_cents)
    # Convert hours input to minutes
    if p[:included_meeting_room_minutes].present?
      p[:included_meeting_room_minutes] = (p[:included_meeting_room_minutes].to_f * 60).to_i
    else
      p[:included_meeting_room_minutes] = nil
    end
    # Convert dollars to cents for overage rate
    if p[:overage_rate_in_cents].present?
      p[:overage_rate_in_cents] = Money.from_amount(p[:overage_rate_in_cents].to_f, "USD").cents
    end
    p
  end
end
