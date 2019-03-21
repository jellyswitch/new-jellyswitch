class SwitchMembership
  include Interactor

  def call
    old_subscription = context.old_subscription
    new_subscription = context.new_subscription

    ActiveRecord::Base.transaction do
      old_subscription.active = false
      new_subscription.active = true

      new_subscription.user_id = old_subscription.user_id # hack for admins switching memberships on behalf of users

      new_subscription.stripe_subscription_id = old_subscription.stripe_subscription_id

      new_subscription.save!
      old_subscription.save!

      Stripe::Subscription.update(
        new_subscription.stripe_subscription_id,
        {
          cancel_at_period_end: false,
          items: [
            {
              id: new_subscription.stripe_subscription.items.data[0].id,
              plan: new_subscription.plan.stripe_plan_id
            }
          ],
      },{
        api_key: new_subscription.plan.operator.stripe_secret_key,
        stripe_account: new_subscription.plan.operator.stripe_user_id
      })

    rescue Exception => e
      context.fail!(message: "Unable to switch membership: #{e.message}")
    end
  end
end