class Billing::Leasing::TerminateOfficeLease
  include Interactor::Organizer

  organize(
    Billing::Subscription::CancelStripeSubscription,
    Billing::Leasing::UpdateEndDate
  )
end
