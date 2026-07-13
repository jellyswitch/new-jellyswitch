
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

    begin
      customer = Stripe::Customer.create({
        email: user.email
      }, {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id
      })
    rescue Stripe::StripeError => e
      # Signup must not 500 because the payment processor rejected the
      # request — the public signup endpoint sees emails Stripe won't accept,
      # and Stripe has transient errors. Fail the interactor like the missing
      # connect case above; keep Honeybadger visibility on the real cause.
      Honeybadger.notify(e)
      context.fail!(message: "We couldn't set up billing for this account. Please try again.")
    end

    payment_profile.stripe_customer_id = customer.id

    if !user.save || !payment_profile.save
      context.fail!(message: "Could not create customer in Stripe.")
    end
    context.user = user
  end
end