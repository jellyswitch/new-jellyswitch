class Billing::Subscription::SetStripeSubscriptionForCancellation
  include Interactor

  def call
    subscription = context.subscription

    subscription.cancelling_at_end_of_billing_period = true

    if !subscription.save
      context.fail!(message: "Unable to set subscription for cancellation.")
    end

    begin
      if subscription.stripe_subscription.status == "canceled"
        Honeybadger.notify("Warning: SetStripeSubscriptionForCancellation called with Subscription: #{subscription.id} / #{subscription.stripe_subscription_id}")
      else
        subscription.set_stripe_to_cancel!
      end
    rescue Exception => e
      undo_deactivate(subscription)
      Honeybadger.notify("Interactor Failure: #{e.message}")
      context.fail!(message: e.message)
    end
  end

  def undo_deactivate(subscription)
    subscription.cancelling_at_end_of_billing_period = false
    if !subscription.save
      context.fail!(message: "Unable to cancel subscription. Your account may not be in good standing -- please contact support.")
    end
  end
end