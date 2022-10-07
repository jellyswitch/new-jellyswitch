
class Billing::Subscription::CancelSubscriptionNow
  include Interactor::Organizer

  organize(
    FeedItems::Create,
    Billing::Credits::Reset,
    CreateNotifications,
    Billing::Subscription::CancelStripeSubscription,
    )
end
