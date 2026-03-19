class Billing::DiscountCodes::ValidateCode
  include Interactor

  delegate :code, :location, :product_type, to: :context

  def call
    return if code.blank?

    discount_codes = DiscountCode.for_location(location)
                                 .for_code(code)
                                 .for_product(product_type)

    if discount_codes.none?
      context.fail!(message: "Invalid discount code.")
      return
    end

    discount_code = discount_codes.first

    unless discount_code.redeemable?
      if discount_code.expired?
        context.fail!(message: "This discount code has expired.")
      elsif discount_code.max_redemptions_reached?
        context.fail!(message: "This discount code has reached its maximum number of uses.")
      else
        context.fail!(message: "This discount code is no longer active.")
      end
      return
    end

    context.discount_code = discount_code
  end
end
