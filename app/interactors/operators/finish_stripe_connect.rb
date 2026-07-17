
class Operators::FinishStripeConnect
  include Interactor

  def call
    stripe_code = context.stripe_code
    operator = context.operator
    location = context.location
    webhook_url = context.webhook_url

    # Store credentials
    response = HTTParty.post("https://connect.stripe.com/oauth/token",
      query: {
        client_secret: ENV['STRIPE_SECRET_KEY'],
        code: stripe_code,
        grant_type: "authorization_code"
      },
      timeout: 10
    )

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
        stripe_access_token: access_token,
        billing_state: "production"
      )

      if location
        location.update(
          stripe_user_id: stripe_user_id,
          stripe_publishable_key: stripe_publishable_key,
          stripe_refresh_token: refresh_token,
          stripe_access_token: access_token
        )
      else
        operator.locations.where(stripe_user_id: nil).update_all(stripe_user_id: stripe_user_id, stripe_publishable_key: stripe_publishable_key, stripe_refresh_token: refresh_token, stripe_access_token: access_token)
      end

      if !result
        context.fail!(message: "There was a problem storing your Stripe credentials.")
      end

      # Enable this later if needed
      # # Overwrite existing user's stripe credentials with new stripe customer in new Stripe Connect account
      # results = []
      # operator.users.non_superadmins.each do |user|
      #   result = CreateStripeCustomer.call(user: user, location: location)
      #   results.push(result)
      # end
      # failures = results.select { |result| !result.success? }
      # if failures.count > 0
      #   context.fail!(message: "Failed to create stripe customers for all users: #{failures.first.message}")
      # end

      sync_plans_to_connected_account(operator, location, stripe_user_id)
    end
  end

  private

  # A (re)connected Stripe account doesn't have the operator's Plan objects on
  # it, so every subscribe fails with "No such plan" until they're recreated.
  # Recreate each Stripe-backed plan on the just-connected account. Per-plan
  # failures must never fail the connect itself — the credentials are already
  # stored and valid — and reconnecting the SAME account makes every create
  # fail with "plan already exists", which is success for our purposes.
  # (This replaced a call to the nonexistent Plan#create_stripe_plan that
  # crashed every connect for an operator with plans, AFTER storing creds.)
  def sync_plans_to_connected_account(operator, location, stripe_user_id)
    target = location ||
      operator.locations.find_by(stripe_user_id: stripe_user_id) ||
      operator.locations.first
    return unless target

    operator.plans.where.not(stripe_plan_id: [nil, ""]).find_each do |plan|
      result = Billing::Plans::CreateStripePlan.call(plan: plan, operator: operator, location: target)
      next if result.success? || result.message.to_s.match?(/already exists/i)

      Honeybadger.notify("FinishStripeConnect: could not recreate plan #{plan.id} on #{stripe_user_id}: #{result.message}")
    end
  end
end
