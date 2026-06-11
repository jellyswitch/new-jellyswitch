class Billing::Subscription::SendCancellationConfirmation
  include Interactor

  # Emails the member confirming their membership cancellation. Runs last in
  # both cancellation organizers so it only fires after the cancellation has
  # actually been applied. Whether the cancel is immediate or scheduled for the
  # end of the billing period is derived from the subscription's state: the
  # cancel-now flow deactivates it first, while cancel-at-period-end leaves it
  # active until the period ends.
  def call
    subscription = context.subscription
    return if subscription.nil?

    user = context.user || subscription.subscribable
    return if user.nil?

    immediate = !subscription.active?

    UserMailer.membership_cancellation_email(
      user,
      context.operator,
      subscription,
      context.location,
      immediate: immediate
    ).deliver_later
  rescue => e
    # A delivery failure must never roll back a successful cancellation.
    Honeybadger.notify(e)
    Rails.logger.error(
      "SendCancellationConfirmation error for subscription #{subscription&.id}: #{e.class}: #{e.message}"
    )
  end
end
