class CreateStripeCustomer
  include Interactor

  def call
    user = context.user

    customer = Stripe::Customer.create({
      email: user.email
    })

    user.stripe_customer_id = customer.id

    if !user.save
      context.fail!(message: "Could not create customer in Stripe.")
    end
    context.user = user
  end
end