
class Billing::DayPasses::UpdatePaymentAndCreateDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::Payment::UpdateUserPayment,
    Billing::DayPasses::CreateStripeInvoice,
    Billing::DayPasses::ChargeDayPassInvoice,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end
