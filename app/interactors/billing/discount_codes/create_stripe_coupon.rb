class Billing::DiscountCodes::CreateStripeCoupon
  include Interactor

  delegate :discount_code, :location, to: :context

  def call
    return unless discount_code.present?

    # Reuse existing Stripe coupon if already created
    if discount_code.stripe_coupon_id.present?
      context.stripe_coupon_id = discount_code.stripe_coupon_id
      return
    end

    coupon_args = {
      id: "dc_#{discount_code.id}_#{SecureRandom.hex(4)}",
      duration: "once"
    }

    if discount_code.discount_type == "percent_off"
      coupon_args[:percent_off] = discount_code.discount_value
    else
      coupon_args[:amount_off] = discount_code.discount_value
      coupon_args[:currency] = "usd"
    end

    stripe_coupon = Stripe::Coupon.create(
      coupon_args,
      api_key: location.stripe_secret_key,
      stripe_account: location.stripe_user_id
    )

    discount_code.update!(stripe_coupon_id: stripe_coupon.id)
    context.stripe_coupon_id = stripe_coupon.id
  rescue Stripe::StripeError => e
    Honeybadger.notify(e)
    context.fail!(message: "Unable to apply discount. Please try again.")
  end
end
