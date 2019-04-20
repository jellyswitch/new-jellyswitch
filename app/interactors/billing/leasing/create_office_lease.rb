class Billing::Leasing::CreateOfficeLease
  include Interactor::Organizer

  organize Billing::Leasing::SaveOfficeLease, Billing::Leasing::CreateStripeSubscription
end
