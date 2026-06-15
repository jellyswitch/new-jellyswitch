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

    # A paid add-on (orderable amenity) makes even a free room chargeable.
    # Checked in Ruby on the just-assigned association — no DB sum on an
    # unsaved record. The member-vs-non-member rate is applied later by
    # amenity_price; here we only need to know "is anything chargeable".
    should_charge ||= reservation.amenities.to_a.any?(&:orderable?)

    if should_charge && context.user.payment_method == "None"
      context.fail!(message: "Please provide payment method!")
    end

    reservation.paid = should_charge
    reservation.user = context.user

    context.reservation = reservation
    context.notifiable = reservation

    if !reservation.save
      context.fail!(message: reservation.errors.full_messages.first || "Unable to create reservation, please try again.")
    end
  end

  def rollback
    context.reservation.destroy if context.reservation&.persisted?
  end
end
