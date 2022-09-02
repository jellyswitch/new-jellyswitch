class Webhooks::SubscriptionDeleted
  include Interactor

  delegate :event, to: :context

  def call
    subscription = Subscription.find_by(stripe_subscription_id: event.data.object.id)
      
    if subscription.present?
      result = SubscriptionDeletedFactory.for(subscription).perform

      if !result.success?
        msg = "SubscriptionDeletedFactory: #{result.message}"
        context.fail!(message: msg)
      end
    else
      # subscription cannot be found
      msg = "customer.subscription.deleted: No such subscription #{event.data.object.id}"
      context.fail!(message: msg)
    end
  end
end