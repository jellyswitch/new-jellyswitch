
Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'],
  secret_key: ENV['STRIPE_SECRET_KEY'],
  test_publishable_key: ENV['STRIPE_TEST_PUBLISHABLE_KEY'],
  test_secret_key: ENV['STRIPE_TEST_SECRET_KEY']
}

Stripe.open_timeout = 10
Stripe.read_timeout = 15

# Auto-retry on transient Stripe failures (RateLimitError, network blips,
# 5xx). The Stripe gem uses idempotency keys so retries are safe; this turns
# the occasional admin-page or webhook RateLimitError into a brief pause
# instead of a Honeybadger alert.
Stripe.max_network_retries = 2
