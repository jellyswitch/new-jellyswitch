
class Billing::DayPasses::CreateDayPassAndCheckin
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::AllocateDayOffice,
    Billing::DayPasses::CreateStripeInvoice,
    Billing::DayPasses::ChargeDayPassInvoice,
    Checkins::AutoCheckin,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end
