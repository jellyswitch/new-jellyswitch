
class CancelSubscription
  include Interactor::Organizer

  organize(
    Billing::Credits::Reset,
    Billing::Subscription::CancelStripeSubscription
  )
end