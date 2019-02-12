class UnmarkCustomerAsOutOfBand
  include Interactor

  def call
    user = context.user
    
    user.subscriptions.active.each do |subscription|
      stripe_subscription = subscription.stripe_subscription
      stripe_subscription.billing = "charge_automatically"
      stripe_subscription.save
    end

    user.out_of_band = false
    if !user.save
      context.fail!(message: "Unable to save user record.")
    end
  rescue Exception => e
    context.fail!(message: e.message)
  end
end