class UpdateUserPayment
  include Interactor

  delegate :user, :token, to: :context

  def call
    return if user.out_of_band?

    if token
      if user.operator.create_or_update_customer_payment(user, token)
        user.update(card_added: true)
      else
        context.fail!(message: "Could not update payment method.")
      end
    end
  end
end
