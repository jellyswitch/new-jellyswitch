class Billing::Subscription::CancelStripeSubscription
  include Interactor

  def call
    subscription = context.subscription

    # TODO: move this to webhook
    # subscription.active = false

    if !subscription.save
      context.fail!(message: "Unable to cancel subscription.")
    end

    begin
      if subscription.stripe_subscription.status == "canceled"
        Honeybadger.notify("Warning: CancelSubscription called with Subscription: #{subscription.id} / #{subscription.stripe_subscription_id}")
      else
        subscription.cancel_stripe!
        subscription.update!(cancelling_at_end_of_billing_period: true)
      end
    rescue Exception => e
      undo_deactivate(subscription)
      Honeybadger.notify("Interactor Failure: #{e.message}")
      context.fail!(message: e.message)
    end
  end

  def undo_deactivate(subscription)
    subscription.active = true
    if !subscription.save
      context.fail!(message: "Unable to cancel subscription. Your account may not be in good standing -- please contact support.")
    end
  end
end