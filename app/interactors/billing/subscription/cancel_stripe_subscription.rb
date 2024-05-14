class Billing::Subscription::CancelStripeSubscription
  include Interactor

  def call
    subscription = context.subscription

    subscription.active = false

    if !subscription.save
      context.fail!(message: "Unable to cancel subscription.")
    end

    begin
      unless subscription.stripe_subscription.status == "canceled"
        subscription.cancel_stripe!
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
