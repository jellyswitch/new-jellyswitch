class Childcare::SendConfirmation
  include Interactor

  delegate :operator, :child_profile, :childcare_slot, :childcare_reservation, :date, to: :context

  def call
    user = childcare_reservation.child_profile.user
    UserMailer.childcare_confirmation_email(childcare_reservation, user).deliver_now
  end
end