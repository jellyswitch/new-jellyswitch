class Billing::Reservations::SaveRoomReservation
  include Interactor
  include FeedItemCreator

  def call
    reservation = Reservation.new(context.reservation_params)

    # Premium/paid rooms charge everyone except members/leaseholders/staff.
    # Day-passers are NOT exempt here (a day pass doesn't cover premium rooms) —
    # should_charge_for_room? bakes in the rate>0 check + production gate.
    should_charge = context.user.should_charge_for_room?(reservation.room, reservation.datetime_in.to_date)

    # Day pass overage check: if user is a day pass holder with meeting room limits
    if !should_charge && context.day_pass_charge_info && context.day_pass_charge_info[:charge_type] == :partial_overage
      should_charge = true
      context.overage_charge_amount = context.day_pass_charge_info[:overage_amount_in_cents]
    end

    # Subscription overage check: if member's plan has meeting room limits
    if !should_charge && context.subscription_charge_info && context.subscription_charge_info[:charge_type] == :partial_overage
      should_charge = true
      context.overage_charge_amount = context.subscription_charge_info[:overage_amount_in_cents]
    end

    if should_charge && context.user.payment_method == "None"
      context.fail!(message: "Please provide payment method!")
    end

    reservation.paid = should_charge
    reservation.user = context.user

    context.reservation = reservation
    context.notifiable = reservation

    if !reservation.save
      # Overlap (someone booked between the room list loading and this tap)
      # is a CONFLICT, not a generic failure — the API returns 409 with the
      # room + window so the app can offer a one-tap list refresh.
      context.conflict = reservation.errors.details[:base].any? { |d| d[:error] == :overlap }
      context.fail!(message: reservation.errors.full_messages.first || "Unable to create reservation, please try again.")
    end
  end

  def rollback
    context.reservation.destroy if context.reservation&.persisted?
  end
end
