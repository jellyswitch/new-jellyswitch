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
      subscription.subscribe_in_stripe!
    rescue Exception => e
      context.fail!(message: e.message)
    end
    context.subscription = subscription
  
  end
end