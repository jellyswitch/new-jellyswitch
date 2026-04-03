
class UnmarkCustomerAsOutOfBand
  include Interactor

  def call
    user = context.user
    
    user.subscriptions.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "charge_automatically"
      stripe_sub.save
    end

    user.out_of_band = false
    if !user.save(context: :payment_method)
      context.fail!(message: "Unable to update payment method: #{user.errors.full_messages.join(', ')}")
    end
  end
end