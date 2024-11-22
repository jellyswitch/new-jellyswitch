class UnpauseMembership
  include Interactor

  delegate :subscription, to: :context

  def call
    ActiveRecord::Base.transaction do
      if !subscription.update(paused: false)
        context.fail!(message: "Subscription couldn't save #{subscription}")
      end

      if !Stripe::Subscription.update(
        subscription.stripe_subscription_id,
          {
            pause_collection: ''
          },
          {
            api_key: subscription.plan.location.stripe_secret_key,
            stripe_account: subscription.plan.location.stripe_user_id
          })

        context.fail!(message: "Stripe Subscription couldn't update")
      end
    end
  end
end
