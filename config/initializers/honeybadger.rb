Honeybadger.configure do |config|
  # Suppress exceptions that represent expected business events, not app bugs.
  # Stripe::CardError fires when the customer's card is declined (insufficient
  # funds, expired card, fraud block, etc.) — handled gracefully by the app
  # and surfaced to the member as a polite "your card was declined" message.
  # Reporting these clutters the dashboard and trains us to ignore alerts.
  config.before_notify do |notice|
    notice.halt! if notice.exception.is_a?(Stripe::CardError)
  end
end
