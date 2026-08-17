
class Billing::Subscription::SaveSubscription
  include Interactor

  delegate :subscription, :user, :location, :start_day, to: :context

  def call
    unless user.card_added_for_location?(location) || user.out_of_band? || user.bill_to_organization?
      context.fail!(message: "Can't add a subscription for someone with no billing info on file.")
    end

    subscription.billable = BillableFactory.for(subscription).billable
    subscription.start_date = start_day

    saved =
      # Locked so two requests can't both pass the duplicate check and then
      # both insert. The lock spans only the check and the INSERT — the Stripe
      # call happens later, in CreateStripeSubscription, so no external round
      # trip is ever made while holding a row lock.
      subscription.subscribable.with_lock do
        if subscription.duplicate_active_membership?
          context.fail!(message: Subscription::DUPLICATE_MEMBERSHIP_MESSAGE)
        end

        subscription.save
      end

    if saved
      context.subscription = subscription
    else
      context.fail!(message: "There was a problem creating this subscription.")
    end
  end

  def rollback
    context.subscription.destroy
  end
end
