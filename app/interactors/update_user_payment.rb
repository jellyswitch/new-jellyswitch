class UpdateUserPayment
  include Interactor

  delegate :user, :token, :out_of_band, to: :context

  def call
    if out_of_band
      user.update(out_of_band: true)
    elsif token && user.operator.create_or_update_customer_payment(user, token)
      user.update(card_added: true)
    else
      context.fail!(message: "Could not update payment method.")
    end
  end
end
