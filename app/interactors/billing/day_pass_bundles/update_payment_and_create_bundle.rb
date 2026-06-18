class Billing::DayPassBundles::UpdatePaymentAndCreateBundle
  include Interactor::Organizer

  organize(
    Billing::DayPassBundles::SaveBundle,
    Billing::Payment::UpdateUserPayment,
    Billing::DayPassBundles::CreateStripeInvoiceForBundle,
    Billing::DayPassBundles::ChargeBundleInvoice,
    Billing::DayPassBundles::CreateNotifications,
    Billing::DayPassBundles::ScheduleBundleEmails
  )
end
