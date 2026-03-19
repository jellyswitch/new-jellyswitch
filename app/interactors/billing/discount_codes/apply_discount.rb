class Billing::DiscountCodes::ApplyDiscount
  include Interactor

  delegate :discount_code, :user, :discountable, :discount_amount_in_cents, to: :context

  def call
    return unless discount_code.present?

    DiscountRedemption.create!(
      discount_code: discount_code,
      user: user,
      discountable: discountable,
      discount_amount_in_cents: discount_amount_in_cents,
      operator_id: discount_code.operator_id
    )

    discount_code.increment!(:redemption_count)
  end
end
