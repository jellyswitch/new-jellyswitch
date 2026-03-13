
class Billing::DayPasses::CreateFreeDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::FindFreeDayPass,
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::CreateStripeInvoice,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end
