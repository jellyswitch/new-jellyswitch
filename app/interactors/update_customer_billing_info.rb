class UpdateCustomerBillingInfo
  include Interactor

  def call
    user = context.user
    token = context.token

    customer = user.stripe_customer
    customer.source = token
    if !customer.save
      context.fail!(message: "Unable to update billing info.")
    end
  rescue Exception => e
    Rollbar.error("Interactor Failure: #{e.message}")
    context.fail!(message: e.message)    
  end
end