class CreateSubscription
  include Interactor
  include FeedItemCreator

  def call
    subscription = context.subscription
    user = context.user
    start_day = context.start_day
    
    if !user.out_of_band?
      result = UpdateUserPayment.call(
        user: user,
        token: context.token
      )
    
      if !result.success?
        context.fail!(message: result.message)
      end
    end

    if !subscription.save
      context.fail!(message: "Failed to create subscription.")
    end

    if user.out_of_band?
      if start_day.present?
        stripe_subscription = Stripe::Subscription.create({
          customer: context.user.stripe_customer_id,
          billing: "send_invoice",
          days_until_due: 30,
          billing_cycle_anchor: start_day.to_i,
          items: [
            { plan: subscription.plan.stripe_plan_id }
          ]}, {
          api_key: subscription.plan.operator.stripe_secret_key,  
          stripe_account: subscription.plan.operator.stripe_user_id
        })
      else
        stripe_subscription = Stripe::Subscription.create({
          customer: context.user.stripe_customer_id,
          billing: "send_invoice",
          days_until_due: 30,
          items: [
            { plan: subscription.plan.stripe_plan_id }
          ]}, {
          api_key: subscription.plan.operator.stripe_secret_key,  
          stripe_account: subscription.plan.operator.stripe_user_id
        })
      end
    else
      if !user.has_billing?
        context.fail!(message: "Can't add a subscription for someone with no billing info on file.")
      end
      
      if start_day.present?
        stripe_subscription = Stripe::Subscription.create({
          customer: context.user.stripe_customer_id,
          billing: "charge_automatically",
          billing_cycle_anchor: start_day.to_i,
          items: [
            { plan: subscription.plan.stripe_plan_id }
          ]}, {
          api_key: subscription.plan.operator.stripe_secret_key,
          stripe_account: subscription.plan.operator.stripe_user_id
        })
      else
        stripe_subscription = Stripe::Subscription.create({
          customer: context.user.stripe_customer_id,
          billing: "charge_automatically",
          items: [
            { plan: subscription.plan.stripe_plan_id }
          ]}, {
          api_key: subscription.plan.operator.stripe_secret_key,
          stripe_account: subscription.plan.operator.stripe_user_id
        })
      end
    end
    
    begin
      subscription.stripe_subscription_id = stripe_subscription.id
      
      if !subscription.save
        context.fail!(message: "There was a problem charging for this subscription.")
      end
    rescue Exception => e
      context.fail!(message: e.message)
    end

    blob = {type: "subscription", subscription_id: subscription.id}
    create_feed_item(user.operator, user, blob)
    context.subscription = subscription
  rescue Exception => e
    Rollbar.error("Interactor Failure: #{e.message}")
    context.fail!(message: e.message)
  end
end

