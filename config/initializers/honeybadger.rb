Honeybadger.configure do |config|
  # Suppress exceptions that represent expected business events, not app bugs.
  config.before_notify do |notice|
    # Card declines: handled gracefully by the app and surfaced to the
    # member as a "your card was declined" message.
    next notice.halt! if notice.exception.is_a?(Stripe::CardError)

    # Heroku H15 (idle connection): router-level signal that a long-running
    # connection (typically ActionCable) was closed by the platform.
    # Infrastructure noise, never an app bug. Match the error_class string
    # since H15 isn't a Ruby exception class.
    next notice.halt! if notice.error_class.to_s.include?("H15")
  end
end
