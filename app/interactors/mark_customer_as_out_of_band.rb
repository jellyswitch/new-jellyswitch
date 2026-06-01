
class MarkCustomerAsOutOfBand
  include Interactor

  def call
    # `customer` is any billable (User or Organization); `user` kept for back-compat.
    customer = context.customer || context.user

    customer.subscriptions.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "send_invoice"
      stripe_sub.days_until_due = 30
      stripe_sub.save
    end

    customer.out_of_band = true
    if !customer.save
      context.fail!(message: "Unable to update payment method: #{customer.errors.full_messages.join(', ')}")
    end
  end
end