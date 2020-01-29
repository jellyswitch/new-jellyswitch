class Childcare::CreateReservation
  include Interactor

  delegate :child_profile, :childcare_slot, :date, to: :context

  def call
    if ChildcareReservation.for_date(date).for_slot(childcare_slot).for_profile(child_profile).count > 0
      # this child profile already has a reservation on this date for this slot
      context.fail!(message: "That child profile already has a reservation for that day.")
    else
      childcare_reservation = ChildcareReservation.new(
        date: date,
        childcare_slot: childcare_slot,
        child_profile: child_profile
      )

      if !childcare_reservation.save
        context.fail!(message: "Something went wrong.")
      end
      context.childcare_reservation = childcare_reservation
    end
  end
end