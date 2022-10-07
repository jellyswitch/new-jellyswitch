class Billing::Leasing::SetOfficeLeaseForTermination
  include Interactor::Organizer

  organize(
    Billing::Leasing::UpdateEndDate,
    Billing::Subscription::SetStripeSubscriptionForCancellation
  )
end