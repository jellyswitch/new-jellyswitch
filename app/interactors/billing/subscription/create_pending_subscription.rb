
class Billing::Subscription::CreatePendingSubscription
  include Interactor
  include ErrorsHelper

  delegate :subscription, :user, :location, :start_day, to: :context

  def call
    if !user.out_of_band? && !user.card_added_for_location?(location)
      # create a pending subscription instead
      subscription.pending = true
      subscription.active = false
    end

    # Only block if there's a truly pending subscription (not one that was canceled/deactivated)
    if user.subscriptions.where(pending: true).where.not(id: subscription.id).count > 0
      context.fail!(message: "Can't add more than one pending memberships. Cancel any existing pending memberships first, and try again.")
    end

    # The sibling guard to the pending one above: a second ACTIVE membership is
    # two Stripe subscriptions and two charges a month. This path doesn't go
    # through SaveSubscription, so it needs the check of its own.
    if subscription.duplicate_active_membership?
      context.fail!(message: Subscription::DUPLICATE_MEMBERSHIP_MESSAGE)
    end

    subscription.billable = BillableFactory.for(subscription).billable
    subscription.start_date = start_day

    if subscription.save
      context.subscription = subscription
    else
      context.fail!(message: "There was a problem creating this subscription (#{errors_for(subscription)}).")
    end
  end
end