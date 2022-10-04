class UnpauseMembership
  include Interactor

  def call
    subscription = context.subscription

    ActiveRecord::Base.transaction do
      subscription.paused = false
      subscription.save!

      Stripe::Subscription.update(
      subscription.stripe_subscription_id,
        { pause_collection: ''},
        {
          api_key: subscription.plan.operator.stripe_secret_key,
          stripe_account: subscription.plan.operator.stripe_user_id
        })
    end
  end
end
