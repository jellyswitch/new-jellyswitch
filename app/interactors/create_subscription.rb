class CreateSubscription
  include Interactor

  def call
    subscription = context.subscription

    if context.token.nil? && !context.user.has_billing?
      context.fail!(message: "Unable to create new stripe customer with nil token.")
    end

    context.user.ensure_stripe_customer(context.token)

    if !subscription.save
      context.fail!(message: "Failed to create subscription.")
    end

    begin
      stripe_subscription = Stripe::Subscription.create({
        customer: context.user.stripe_customer_id,
        items: [
          { plan: subscription.plan.stripe_plan_id }
        ]
      })
      subscription.stripe_subscription_id = stripe_subscription.id
      if !subscription.save
        context.fail!(message: "There was a problem charging for this subscription.")
      end
    rescue Exception => e
      context.fail!(message: e.message)
    end
    context.subscription = subscription
  end
end