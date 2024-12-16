
class CreateStripeCustomer
  include Interactor

  def call
    user = context.user
    location = context.location

    payment_profile = user.user_payment_profiles.find_or_create_by(location: location)

    if payment_profile.stripe_customer_id
      context.user = user
      return
    end

    if !location&.stripe_user_id
      context.fail!(message: "This location has not set up Stripe connect yet. Please reach out to the location contact for more information.")
    end

    customer = Stripe::Customer.create({
      email: user.email
    }, {
      api_key: location.stripe_secret_key,
      stripe_account: location.stripe_user_id
    })

    payment_profile.stripe_customer_id = customer.id

    if !user.save || !payment_profile.save
      context.fail!(message: "Could not create customer in Stripe.")
    end
    context.user = user
  end
end