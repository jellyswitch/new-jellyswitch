class Billing::DayPassBundles::CreateBundle
  include Interactor::Organizer

  organize(
    Billing::DayPassBundles::SaveBundle,
    Billing::DayPassBundles::CreateStripeInvoiceForBundle,
    Billing::DayPassBundles::ChargeBundleInvoice
  )
end
