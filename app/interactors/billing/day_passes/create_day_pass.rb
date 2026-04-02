
class Billing::DayPasses::CreateDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::CreateStripeInvoice,
    Billing::DayPasses::ChargeDayPassInvoice,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end
