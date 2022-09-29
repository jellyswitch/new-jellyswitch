
class SetSubscriptionForCancellation
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    Billing::Subscription::SetStripeSubscriptionForCancellation
  )
end