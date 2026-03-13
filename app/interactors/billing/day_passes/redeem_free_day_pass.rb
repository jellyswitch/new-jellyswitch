
class Billing::DayPasses::RedeemFreeDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::CreateStripeInvoice,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails
  )
end