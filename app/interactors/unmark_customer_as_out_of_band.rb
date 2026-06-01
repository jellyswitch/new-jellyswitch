
class UnmarkCustomerAsOutOfBand
  include Interactor

  def call
    # `customer` is any billable (User or Organization); `user` kept for back-compat.
    customer = context.customer || context.user

    customer.subscriptions.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "charge_automatically"
      stripe_sub.save
    end

    customer.out_of_band = false
    if !customer.save
      context.fail!(message: "Unable to update payment method: #{customer.errors.full_messages.join(', ')}")
    end
  end
end