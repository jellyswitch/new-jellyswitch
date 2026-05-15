Honeybadger.configure do |config|
  # Suppress exceptions that represent expected business events or known
  # transient infrastructure noise, not app bugs.
  config.before_notify do |notice|
    # Card declines: handled gracefully by the app and surfaced to the
    # member as a "your card was declined" message.
    next notice.halt! if notice.exception.is_a?(Stripe::CardError)

    # Redis SSL hiccups: Heroku Redis occasionally resets a TLS connection.
    # The Redis client reconnects on next use, no app-level damage. Pattern
    # match on backtrace so we don't accidentally suppress a connection
    # error from somewhere else (e.g. an outbound HTTP call that genuinely
    # warrants attention).
    if notice.exception.is_a?(Errno::ECONNRESET) || notice.exception.is_a?(OpenSSL::SSL::SSLError)
      from_redis = notice.exception.backtrace&.any? { |line| line.include?("/redis-") || line.include?("/redis/connection/") }
      next notice.halt! if from_redis
    end

    # Note: Heroku platform errors (H15 idle connection, H12 timeout, etc.)
    # are ingested by Honeybadger directly from the Heroku log drain via
    # the Honeybadger Heroku addon — they never pass through this Ruby
    # callback. Suppress them in the Honeybadger project dashboard
    # (Settings → Heroku integration / Insights filters), not here.
  end
end
