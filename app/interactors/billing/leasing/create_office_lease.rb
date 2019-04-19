class Billing::Leasing::CreateOfficeLease
  include Interactor::Organizer

  organize SaveOfficeLease, CreateStripeSubscription
end
