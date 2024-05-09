class Billing::Leasing::SetOfficeLeaseForTermination
  include Interactor::Organizer

  organize(
    Billing::Subscription::SetStripeSubscriptionForCancellation,
    Billing::Leasing::UpdateEndDateToPeriodEnd
  )
end
