# typed: true
class CancelSubscription
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    Billing::Credits::Reset,
    Billing::Subscription::CancelStripeSubscription
  )
end