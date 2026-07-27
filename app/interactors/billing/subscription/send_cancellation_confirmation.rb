class Billing::Subscription::SendCancellationConfirmation
  include Interactor

  # Emails the member confirming their membership cancellation. Runs last in
  # both cancellation organizers so it only fires after the cancellation has
  # actually been applied. Whether the cancel is immediate or scheduled for the
  # end of the billing period is derived from the subscription's state: the
  # cancel-now flow deactivates it first, while cancel-at-period-end leaves it
  # active until the period ends.
  #
  # Commitment-scheduled cancels (the in_commitment? controller branches, which
  # bypass both organizers) call this directly with commitment_ends_on — the
  # email then states that billing continues through that date.
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
      immediate: immediate,
      commitment_ends_on: context.commitment_ends_on
    ).deliver_later
  rescue => e
    # A delivery failure must never roll back a successful cancellation.
    Honeybadger.notify(e)
    Rails.logger.error(
      "SendCancellationConfirmation error for subscription #{subscription&.id}: #{e.class}: #{e.message}"
    )
  end
end
