class Billing::Subscription::CreateSubscription
  include Interactor::Organizer

  organize(
    Billing::Payment::UpdateUserPayment,
    SaveSubscription,
    CreateStripeSubscription,
    CreateNotifications
  )
end
