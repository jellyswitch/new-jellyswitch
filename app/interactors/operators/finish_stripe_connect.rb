class Operators::FinishStripeConnect
  include Interactor

  def call
    stripe_code = context.stripe_code
    operator = context.operator
    webhook_url = context.webhook_url

    # Store credentials
    response = HTTParty.post("https://connect.stripe.com/oauth/token", 
      query: {
        client_secret: ENV['STRIPE_SECRET_KEY'],
        code: stripe_code,
        grant_type: "authorization_code"
    })
    
    if response["error"].present?
      context.fail!(message: response["error_description"])
    else
      stripe_user_id = response["stripe_user_id"]
      stripe_publishable_key = response["stripe_publishable_key"]
      refresh_token = response["refresh_token"]
      access_token = response["access_token"]

      result = operator.update(
        stripe_user_id: stripe_user_id,
        stripe_publishable_key: stripe_publishable_key,
        stripe_refresh_token: refresh_token,
        stripe_access_token: access_token
      )

      if !result
        context.fail!(message: "There was a problem storing your Stripe credentials.")
      end
    end
  end
end