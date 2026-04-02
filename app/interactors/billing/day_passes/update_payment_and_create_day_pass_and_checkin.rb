
class Billing::DayPasses::UpdatePaymentAndCreateDayPassAndCheckin
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::Payment::UpdateUserPayment,
    Billing::DayPasses::CreateStripeInvoice,
    Billing::DayPasses::ChargeDayPassInvoice,
    Checkins::AutoCheckin,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end
