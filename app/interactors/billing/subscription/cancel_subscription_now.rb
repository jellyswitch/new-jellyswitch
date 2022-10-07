
class Billing::Subscription::CancelSubscriptionNow
  include Interactor::Organizer

  organize(
    Billing::Subscription::CancelStripeSubscription,
    FeedItems::Create,
    Billing::Credits::Reset,
    CreateNotifications
  )
end
