class UpdateUserPayment
  include Interactor

  delegate :user, :token, to: :context

  def call
    return if user.out_of_band?

    if token
      unless user.operator.create_or_update_customer_payment(user, token)
        context.fail!(message: "Could not update payment method.")
      end
    end
  end
end
