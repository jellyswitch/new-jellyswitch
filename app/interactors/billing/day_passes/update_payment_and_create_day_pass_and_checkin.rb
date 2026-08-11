
class Billing::DayPasses::UpdatePaymentAndCreateDayPassAndCheckin
  include Interactor::Organizer

  organize(
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::AllocateDayOffice,
    Billing::Payment::UpdateUserPayment,
    Billing::DayPasses::CreateStripeInvoice,
    Billing::DayPasses::ChargeDayPassInvoice,
    Checkins::AutoCheckin,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails,
    # LAST: the Day Office confirmation email must imply a cleared charge.
    Billing::DayPasses::NotifyDayOfficeAssigned
  )
end
