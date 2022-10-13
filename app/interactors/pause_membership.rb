class PauseMembership
  include Interactor

  delegate :subscription, to: :context

  def call
    ActiveRecord::Base.transaction do
      if !subscription.update(paused: true)
        context.fail!(message: "Subscription couldn't save: #{subscription}")
      end

      if !Stripe::Subscription.update(
        subscription.stripe_subscription_id,
        {
          pause_collection:
          {
            behavior: 'void',
            resumes_at: subscription.resumes_at.to_i
          }
        },
        {
          api_key: subscription.plan.operator.stripe_secret_key,
          stripe_account: subscription.plan.operator.stripe_user_id
        })

        context.fail!(message: "Stripe Subscription couldn't update")
      end
    end
  end
end
