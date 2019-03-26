class UpdateUserPayment
  include Interactor

  def call
    token = context.token
    user = context.user

    if user.has_billing?
      # We're trying to update it anyway
      if token.nil?
        # This interactor is called every time we want
        # to charge the user. If we pass a token, then we update
        # the payment source. If there is no token, it means we don't
        # actually want to update the payment info. Just to check to make
        # sure it exists.
      else
        update_payment(user, token)
      end
    else
      # We're adding billing for the first time
      update_payment(user, token)
    end

  rescue Exception => e
    Rollbar.error("Interactor Failure: #{e.message}")
    context.fail!(message: e.message)
  end

  def update_payment(user, token)
    stripe_customer = user.stripe_customer
    stripe_customer.source = token
    if !stripe_customer.save
      context.fail!(message: "Could not update payment method.")
    end
  end
end