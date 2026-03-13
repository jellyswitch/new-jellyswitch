
class Billing::Subscription::ActivatePendingSubscription
  include Interactor::Organizer

  organize(
    Billing::Subscription::ActivateSubscription,
    Billing::Subscription::CreateStripeSubscription,
    CreateNotifications,
    Billing::Subscription::ScheduleSubscriptionEmails
  )
end