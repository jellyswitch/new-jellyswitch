
class Billing::DayPasses::CreateDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::CreateStripeInvoice,
    CreateNotificationsAsync
  )
end
