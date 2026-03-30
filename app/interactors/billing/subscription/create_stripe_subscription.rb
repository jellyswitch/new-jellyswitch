
class Billing::Subscription::CreateStripeSubscription
  include Interactor
  delegate :subscription, :operator, :location, :start_day, to: :context

  def call
    user = subscription.subscribable

    # Skip Stripe for $0 plans — no payment needed
    if subscription.plan.amount_in_cents.to_i == 0
      subscription.update(active: true)
      context.notifiable = subscription
      return
    end

    # Create Stripe coupon if discount code provided
    if context.discount_code.present?
      coupon_result = Billing::DiscountCodes::CreateStripeCoupon.call(
        discount_code: context.discount_code,
        location: location
      )
      if coupon_result.success?
        context.stripe_coupon_id = coupon_result.stripe_coupon_id
      end
    end

    begin
      stripe_subscription = location.create_stripe_subscription(subscription, coupon: context.stripe_coupon_id)
    rescue StandardError => e
      context.fail!(message: e.message)
    end

    if subscription.update(stripe_subscription_id: stripe_subscription.id)
      context.notifiable = subscription

      # Record discount redemption
      if context.discount_code.present?
        discount_amount = context.discount_code.calculate_discount(subscription.plan.amount_in_cents)
        Billing::DiscountCodes::ApplyDiscount.call(
          discount_code: context.discount_code,
          user: user,
          discountable: subscription,
          discount_amount_in_cents: discount_amount
        )
      end
    else
      context.fail!(message: "Could not save subscription.")
    end
  end
end
