class Billing::Reservations::SaveRoomReservation
  include Interactor
  include FeedItemCreator

  def call
    reservation = Reservation.new(context.reservation_params)

    should_charge = context.user.should_charge_for_reservation?(reservation.room.location, reservation.datetime_in.to_date) && reservation.room.hourly_rate_in_cents > 0

    # Day pass overage check: if user is a day pass holder with meeting room limits
    if !should_charge && context.day_pass_charge_info && context.day_pass_charge_info[:charge_type] == :partial_overage
      should_charge = true
      context.overage_charge_amount = context.day_pass_charge_info[:overage_amount_in_cents]
    end

    if should_charge && context.user.payment_method == "None"
      context.fail!(message: "Please provide payment method!")
    end

    reservation.paid = should_charge
    reservation.user = context.user

    context.reservation = reservation
    context.notifiable = reservation

    if !reservation.save
      context.fail!(message: "Unable to create reservation, please try again.")
    end
  end

  def rollback
    context.reservation.destroy if context.reservation&.persisted?
  end
end
