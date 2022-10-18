class Webhooks::SubscriptionUpdated
  include Interactor

  delegate :event, to: :context

  def call
    subscription = Subscription.find_by(stripe_subscription_id: event.data.object.id)
      
    if subscription.present? && subscription.plan.individual?
      if subscription.paused?
        if event.data.object.pause_collection.blank?
          result = UnpauseMembership.call(
            subscription: subscription
          )
          if !result.success?
            context.fail!(message: result.message)
          end
        else
          # some other update, not an unpause
        end
      else
        # subscription is active and we're updating it
      end
    else
      # this is not a membership (maybe an office lease) and/or this is missing from our DB
      # so we do nothing
    end
  end
end