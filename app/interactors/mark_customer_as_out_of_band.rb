
class MarkCustomerAsOutOfBand
  include Interactor

  def call
    user = context.user
    
    user.subscriptions.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "send_invoice"
      stripe_sub.days_until_due = 30
      stripe_sub.save
    end

    user.out_of_band = true
    if !user.save
      context.fail!(message: "Unable to save user record.")
    end
  end
end