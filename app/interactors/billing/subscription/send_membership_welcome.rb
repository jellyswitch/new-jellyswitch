class Billing::Subscription::SendMembershipWelcome
  include Interactor

  # Confirms a NEW membership to the member at signup. Runs last in the create
  # organizers so it only fires after the subscription actually exists. There is
  # otherwise no hardcoded welcome/receipt email — only an operator-configurable
  # onboarding template (often unset) and Stripe's own receipts — so a new member
  # could get zero confirmation. Plan switches go through SwitchMembership, which
  # does NOT run this, so a welcome fires only on the initial signup.
  #
  # Best-effort: a delivery failure must never roll back a committed signup.
  def call
    subscription = context.subscription
    return if subscription.nil?

    user = context.user || subscription.subscribable
    return if user&.email.blank?

    operator = context.operator || subscription.plan&.operator || context.location&.operator
    return if operator.nil?

    UserMailer.membership_welcome_email(
      user, operator, subscription, context.location
    ).deliver_later
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error(
      "SendMembershipWelcome error for subscription #{subscription&.id}: #{e.class}: #{e.message}"
    )
  end
end
