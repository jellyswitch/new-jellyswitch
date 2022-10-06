class Webhooks::SubscriptionUpdated
  include Interactor

  delegate :event, to: :context

  def call
    subscription = Subscription.find_by(stripe_subscription_id: event.data.object.id)
      
    if subscription.present?
      if subscription.plan.individual?
        if subscription.paused?
          result = UnpauseMembership.call(
            subscription: subscription
          )
        end
      end
    end

      if !result.success?
        msg = "UnpauseMembership: #{result.message}"
        context.fail!(message: msg)
      end
    else
      # subscription cannot be found
      msg = "customer.subscription.updated: No such subscription #{event.data.object.id}"
      context.fail!(message: msg)
    end
  end
end