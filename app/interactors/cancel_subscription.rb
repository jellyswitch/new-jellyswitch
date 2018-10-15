class CancelSubscription
  include Interactor

  def call
    subscription = context.subscription

    subscription.active = false

    if !subscription.save
      context.fail!(message: "Unable to cancel subscription.")
    end

    begin
      subscription.cancel_stripe!
    rescue Exception => e
      undo_deactivate(subscription)
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