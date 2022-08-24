# typed: true
class CancelSubscription
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    Billing::Subscription::CancelStripeSubscription
  )
end