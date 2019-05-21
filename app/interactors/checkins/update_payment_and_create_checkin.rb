class Checkins::UpdatePaymentAndCreateCheckin
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    CreateCheckin
  )
end
