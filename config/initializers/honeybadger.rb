Honeybadger.configure do |config|
  # Suppress exceptions that represent expected business events or known
  # transient infrastructure noise, not app bugs.
  config.before_notify do |notice|
    # Card declines: handled gracefully by the app and surfaced to the
    # member as a "your card was declined" message.
    next notice.halt! if notice.exception.is_a?(Stripe::CardError)

    # Empty multipart body POSTs to root — vulnerability probes from bots
    # (one repeat offender at 103.215.75.70 fires ~50/day on tml.jellyswitch.com).
    # Rack's body parser raises this before Rails routing, so it can't be
    # rescued in a controller. The probe can't do anything to the app, but
    # without this filter the bot eats ~1% of our monthly Honeybadger quota
    # and buries real errors. Real form submissions don't hit this — a
    # legitimate multipart request has a non-empty body by construction.
    next notice.halt! if notice.exception.is_a?(Rack::Multipart::EmptyContentError)

    # Redis SSL hiccups: Heroku Redis occasionally resets a TLS connection.
    # The Redis client reconnects on next use, no app-level damage. Pattern
    # match on backtrace so we don't accidentally suppress a connection
    # error from somewhere else (e.g. an outbound HTTP call that genuinely
    # warrants attention).
    if notice.exception.is_a?(Errno::ECONNRESET) || notice.exception.is_a?(OpenSSL::SSL::SSLError)
      from_redis = notice.exception.backtrace&.any? { |line| line.include?("/redis-") || line.include?("/redis/connection/") }
      next notice.halt! if from_redis
    end

    # `heroku run rails runner` one-liners that raise during eval get
    # flushed by Honeybadger's at_exit hook with no controller / job /
    # task context — component reports as "at_exit" and action is nil.
    # These are interactive ad-hoc prod queries (usually column-name
    # typos, e.g. `users.admin_created` when the column is the virtual
    # attr_accessor only); they aren't user-facing errors and bury real
    # notifications in the dashboard. Sidekiq, ActiveJob, and rake task
    # errors all set component to their own class name, so they're
    # unaffected by this filter.
    next notice.halt! if notice.component == "at_exit" && notice.action.nil?

    # Note: Heroku platform errors (H15 idle connection, H12 timeout, etc.)
    # are ingested by Honeybadger directly from the Heroku log drain via
    # the Honeybadger Heroku addon — they never pass through this Ruby
    # callback. Suppress them in the Honeybadger project dashboard
    # (Settings → Heroku integration / Insights filters), not here.
  end
end
