module RoomsHelper
  def room_params
    p = params.require(:room).permit(
      :allow_shorter_reservation_duration,
      :name,
      :description,
      :capacity,
      :square_footage,
      :photo,
      :visible,
      :rentable,
      :hourly_rate_in_cents,
      :include_with_day_pass,
      :credit_cost,
      amenities_attributes: [:id, :name, :price, :membership_price, :_destroy],
    )

    dollars = Money.from_amount(p[:hourly_rate_in_cents].to_i, "USD")
    p[:hourly_rate_in_cents] = dollars.cents
    p
  end
end
