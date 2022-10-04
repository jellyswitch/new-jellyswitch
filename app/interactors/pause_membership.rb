class PauseMembership
  include Interactor

  def call
    subscription = context.subscription
    resumes_at = context.resumes_at

    ActiveRecord::Base.transaction do
      subscription.paused = true
      subscription.save!

      Stripe::Subscription.update(
        subscription.stripe_subscription_id,
        { pause_collection:
          { behavior: 'void',
            resumes_at: resumes_at
          }
        },
        {
          api_key: subscription.plan.operator.stripe_secret_key,
          stripe_account: subscription.plan.operator.stripe_user_id
        })
    end
  end
end
