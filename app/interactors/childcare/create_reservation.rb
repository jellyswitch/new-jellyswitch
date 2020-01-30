class Childcare::CreateReservation
  include Interactor::Organizer

  organize(
    Childcare::SaveReservation,
    CreateNotifications
  )
end