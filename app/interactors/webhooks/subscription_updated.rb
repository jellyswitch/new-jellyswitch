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
          if result.success?
            ok
          else
            error(result.message)
          end
        else
          # some other update, not an unpause
          ok
        end
      else
        # subscription is active and we're updating it
        ok
      end
    else
      # this is not a membership (maybe an office lease) and/or this is missing from our DB
      # so we do nothing
      ok
    end

    if !result.success?
      msg = "UnpauseMembership: #{result.message}"
      context.fail!(message: msg)
    else
      # subscription cannot be found
      msg = "customer.subscription.updated: No such subscription #{event.data.object.id}"
      context.fail!(message: msg)
    end
  end
end