class Billing::Reservations::OveragePreview
  # Prospective meeting-room overage (cents) for a booking of `minutes` on
  # `date`, drawn against `day_pass_type`'s included minutes net of the member's
  # other include_with_day_pass bookings that day. Mirrors
  # ChargeCalculator#day_pass_overage_cents so the quote matches the capture.
  # `day_pass_type` may be one that will be minted/bought post-commit.
  def self.cents(user:, location:, date:, minutes:, day_pass_type:, reservation_id: nil)
    over = over_minutes(user: user, date: date, minutes: minutes,
                        day_pass_type: day_pass_type, reservation_id: reservation_id)
    return 0 if over <= 0

    over_rounded = (over / 15.0).ceil * 15
    ((location.overage_rate_in_cents.to_f / 60.0) * over_rounded).round
  end

  # RAW minutes past the pass's remaining allowance (no 15-minute billing
  # rounding, no rate applied). EnforceMeteredRoomLimit uses this to make a
  # configured cap real even where the overage rate is $0 and there is
  # therefore nothing to charge.
  def self.over_minutes(user:, date:, minutes:, day_pass_type:, reservation_id: nil)
    return 0 unless day_pass_type&.has_meeting_room_limit?

    allotment = day_pass_type.included_meeting_room_minutes.to_i
    other = Reservation.joins(:room)
                       .where(user_id: user.id, cancelled: false)
                       .where(datetime_in: date.beginning_of_day..date.end_of_day)
                       .where(rooms: { include_with_day_pass: true })
                       .where.not(id: reservation_id)
                       .where(day_office_pass_id: nil) # office holds never draw the allowance (ADR 0026)
                       .sum(:minutes)
    free_remaining = [allotment - other, 0].max
    [minutes.to_i - free_remaining, 0].max
  end
end
