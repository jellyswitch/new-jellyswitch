class Childcare::CreateReservation
  include Interactor::Organizer

  organize(
    Childcare::SaveReservation,
    Childcare::ChargeCredits,
    CreateNotifications
  )
end