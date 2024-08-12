class Billing::Leasing::UpdateLeasePrice
  include Interactor::Organizer

  organize(
    Billing::Leasing::UpdateStripeSubscriptionPrice,
    Billing::Plans::UpdateLocalPlanPrice
  )
end
