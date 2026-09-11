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
      :features_text,
      amenities_attributes: [:id, :name, :price, :membership_price, :_destroy],
    )

    # Features arrive as one line per feature (the mobile admin API sends the
    # array directly); blank lines are dropped so "clear the box" empties it.
    if p.key?(:features_text)
      p[:features] = p.delete(:features_text).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
    end

    dollars = Money.from_amount(p[:hourly_rate_in_cents].to_i, "USD")
    p[:hourly_rate_in_cents] = dollars.cents
    p
  end
end
