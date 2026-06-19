# Computes what a reservation should actually cost in cents for a given
# duration. The reservation itself is excluded from prior-period usage
# so settling doesn't double-count overage against itself.
#
# Used by CaptureHold (settling at end-of-reservation) and AuthorizeHold
# (placing the hold on a reservation extension).
class Billing::Reservations::ChargeCalculator
  def self.call(reservation:, minutes:)
    new(reservation: reservation, minutes: minutes).call
  end

  def initialize(reservation:, minutes:)
    @reservation = reservation
    @minutes = minutes.to_i
  end

  def call
    return 0 if minutes <= 0
    base_room_or_overage + amenity_cents
  end

  private

  attr_reader :reservation, :minutes

  def room
    @room ||= reservation.room
  end

  def location
    @location ||= room.location
  end

  def user
    @user ||= reservation.user
  end

  def date
    @date ||= reservation.datetime_in.to_date
  end

  # The room/overage portion — unchanged from the original `call` logic.
  def base_room_or_overage
    if room.hourly_rate_in_cents.to_i > 0
      # Members/leaseholders/staff are exempt from priced-room hourly charges —
      # the same gate the create path applies via should_charge_for_room?.
      # Without this, editing or extending a booking (which re-prices through
      # here via AuthorizeHold) places a hold + flips paid=true on an exempt
      # member's reservation, wrongly charging them.
      return 0 unless user.should_charge_for_room?(room, date)

      return ((room.hourly_rate_in_cents * minutes) / 60.0).round
    end

    day_pass = user.day_passes.where(day: date).first
    if day_pass && day_pass.day_pass_type&.has_meeting_room_limit?
      return day_pass_overage_cents(day_pass)
    end

    sub = user.active_subscription_for_location(location)
    if sub && sub.plan&.has_meeting_room_limit?
      return subscription_overage_cents(sub)
    end

    0
  end

  # Flat add-on cost (member vs non-member aware), independent of minutes.
  # Mirrors Reservation#amenity_price so the hold and the capture agree.
  def amenity_cents
    reservation.amenity_price
  end

  def day_pass_overage_cents(day_pass)
    allotment = day_pass.day_pass_type.included_meeting_room_minutes.to_i
    other_used = Reservation.joins(:room)
                            .where(user_id: reservation.user_id, cancelled: false)
                            .where(datetime_in: date.beginning_of_day..date.end_of_day)
                            .where('rooms.hourly_rate_in_cents = 0 OR rooms.hourly_rate_in_cents IS NULL')
                            .where.not(id: reservation.id)
                            .sum(:minutes)
    free_remaining = [allotment - other_used, 0].max
    over = [minutes - free_remaining, 0].max
    return 0 if over <= 0
    over_rounded = (over / 15.0).ceil * 15
    rate_per_min = day_pass.day_pass_type.overage_rate_in_cents.to_f / 60.0
    (rate_per_min * over_rounded).round
  end

  def subscription_overage_cents(sub)
    allotment = sub.plan.included_meeting_room_minutes.to_i
    period_start, period_end = sub.current_billing_period
    return 0 unless period_start
    other_used = Reservation.where(user_id: reservation.user_id, cancelled: false)
                            .where(datetime_in: period_start..period_end)
                            .where.not(id: reservation.id)
                            .sum(:minutes)
    free_remaining = [allotment - other_used, 0].max
    over = [minutes - free_remaining, 0].max
    return 0 if over <= 0
    over_rounded = (over / 15.0).ceil * 15
    rate_per_min = sub.plan.overage_rate_in_cents.to_f / 60.0
    (rate_per_min * over_rounded).round
  end
end
