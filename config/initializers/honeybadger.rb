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

    # Empty multipart bodies: Rack 3+ raises EmptyContentError when a request
    # advertises Content-Type: multipart/form-data but the body is empty.
    # Pre-Rack-3 silently returned empty params. No browser produces this —
    # in production it's exclusively bots/vulnerability scanners POSTing junk
    # to "/". Mapped to 400 in config/application.rb so the client gets a
    # proper Bad Request response; suppressed here so the bot traffic doesn't
    # drown out real errors. If a legitimate code path ever raises this, it
    # will still appear in Rails logs.
    if defined?(Rack::Multipart::EmptyContentError) && notice.exception.is_a?(Rack::Multipart::EmptyContentError)
      next notice.halt!
    end

    # Note: Heroku platform errors (H15 idle connection, H12 timeout, etc.)
    # are ingested by Honeybadger directly from the Heroku log drain via
    # the Honeybadger Heroku addon — they never pass through this Ruby
    # callback. Suppress them in the Honeybadger project dashboard
    # (Settings → Heroku integration / Insights filters), not here.
  end
end
