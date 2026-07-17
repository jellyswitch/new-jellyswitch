namespace :staging do
  # Run after every prod -> staging pg:copy (see docs/recommendations/
  # 2026-07-17-staging-refresh-stripe-secrets.md). The Stripe Connect OAuth
  # columns copied from prod hold LIVE credentials for the connected accounts:
  # stripe_access_token is a live-mode secret key. App code never reads them
  # for API calls (platform env keys + Stripe-Account header everywhere), so
  # nulling them changes nothing functionally on staging.
  #
  # stripe_user_id is kept — it's not a secret, and staging's test-mode calls
  # still need the connected account id.
  desc "Null live Stripe OAuth secrets copied from prod (safe: refuses to run against live keys)"
  task scrub_stripe_secrets: :environment do
    secret_key = Rails.configuration.stripe[:secret_key].to_s
    unless secret_key.start_with?("sk_test_")
      abort "Refusing to scrub: STRIPE_SECRET_KEY is not a test key, so this " \
            "does not look like a staging environment."
    end

    scrubbed = {
      stripe_access_token: nil,
      stripe_refresh_token: nil,
      stripe_publishable_key: nil,
    }

    locations = Location.where.not(stripe_access_token: nil)
                        .or(Location.where.not(stripe_refresh_token: nil))
                        .or(Location.where.not(stripe_publishable_key: nil))
                        .update_all(scrubbed)
    operators = Operator.where.not(stripe_access_token: nil)
                        .or(Operator.where.not(stripe_refresh_token: nil))
                        .or(Operator.where.not(stripe_publishable_key: nil))
                        .update_all(scrubbed)

    puts "Scrubbed Stripe OAuth secrets: #{locations} locations, #{operators} operators."
  end
end
