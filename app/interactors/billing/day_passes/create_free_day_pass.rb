
class Billing::DayPasses::CreateFreeDayPass
  include Interactor::Organizer

  organize(
    Billing::DayPasses::FindFreeDayPass,
    Billing::DayPasses::SaveDayPass,
    Billing::DayPasses::AllocateDayOffice,
    Billing::DayPasses::CreateStripeInvoice,
    CreateNotifications,
    Billing::DayPasses::ScheduleDayPassEmails,
    # LAST: the Day Office confirmation email must imply a cleared charge.
    Billing::DayPasses::NotifyDayOfficeAssigned
  )
end
