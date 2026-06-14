# Decides which exceptions Honeybadger should drop: expected business events
# and known transient infrastructure noise, not app bugs. Extracted from the
# before_notify block (below) so the logic is unit-testable — see
# test/initializers/honeybadger_noise_filter_test.rb. (Same pattern as
# RackAttackConfig.)
module HoneybadgerNoiseFilter
  def self.suppress?(notice)
    exception = notice.exception

    # Card declines: handled gracefully by the app and surfaced to the
    # member as a "your card was declined" message.
    return true if exception.is_a?(Stripe::CardError)

    # Empty multipart body POSTs to root — vulnerability probes from bots
    # (one repeat offender at 103.215.75.70 fires ~50/day on tml.jellyswitch.com).
    # Rack's body parser raises this before Rails routing, so it can't be
    # rescued in a controller. The probe can't do anything to the app, but
    # without this filter the bot eats ~1% of our monthly Honeybadger quota
    # and buries real errors. Real form submissions don't hit this — a
    # legitimate multipart request has a non-empty body by construction.
    return true if exception.is_a?(Rack::Multipart::EmptyContentError)

    # Redis connection/timeout transients from the no-HA Mini Redis: read/write
    # timeouts, failovers, and dropped sockets when Heroku restarts or relocates
    # the instance. The client reconnects on next use and Sidekiq re-fetches any
    # unacked job, so there's no app-level damage. The RedisClient:: / Redis::
    # namespaces already prove the error is Redis-layer, so (unlike the generic
    # socket errors below) no backtrace check is needed. CommandError is
    # deliberately NOT in this family — an OOM ("command not allowed when used
    # memory > maxmemory") or WRONGTYPE is a real problem we want surfaced.
    return true if redis_connection_transient?(exception)

    # Redis SSL hiccups: Heroku Redis occasionally resets a TLS connection.
    # Errno::ECONNRESET / SSLError are generic and can come from anywhere
    # (e.g. an outbound HTTP call that genuinely warrants attention), so only
    # suppress when the backtrace shows the error came from the Redis client.
    return true if redis_socket_error?(exception)

    # `heroku run rails runner` one-liners that raise during eval get
    # flushed by Honeybadger's at_exit hook with no controller / job /
    # task context — component reports as "at_exit" and action is nil.
    # These are interactive ad-hoc prod queries (usually column-name
    # typos, e.g. `users.admin_created` when the column is the virtual
    # attr_accessor only); they aren't user-facing errors and bury real
    # notifications in the dashboard. Sidekiq, ActiveJob, and rake task
    # errors all set component to their own class name, so they're
    # unaffected by this filter.
    return true if notice.component == "at_exit" && notice.action.nil?

    false
  end

  # Transient connection/timeout errors from either Redis client layer:
  #   - redis-client (Sidekiq's client): RedisClient::ConnectionError covers
  #     ReadTimeoutError, WriteTimeoutError, FailoverError, CannotConnectError.
  #   - redis-rb (the $redis / ActiveJob::TrafficControl client):
  #     Redis::BaseConnectionError covers TimeoutError + CannotConnectError.
  def self.redis_connection_transient?(exception)
    (defined?(RedisClient::ConnectionError) && exception.is_a?(RedisClient::ConnectionError)) ||
      (defined?(Redis::BaseConnectionError) && exception.is_a?(Redis::BaseConnectionError))
  end

  def self.redis_socket_error?(exception)
    return false unless exception.is_a?(Errno::ECONNRESET) || exception.is_a?(OpenSSL::SSL::SSLError)

    exception.backtrace&.any? { |line| line.include?("/redis-") || line.include?("/redis/connection/") } || false
  end
end

Honeybadger.configure do |config|
  # Suppress exceptions that represent expected business events or known
  # transient infrastructure noise, not app bugs. See HoneybadgerNoiseFilter.
  config.before_notify do |notice|
    next notice.halt! if HoneybadgerNoiseFilter.suppress?(notice)

    # Note: Heroku platform errors (H15 idle connection, H12 timeout, etc.)
    # are ingested by Honeybadger directly from the Heroku log drain via
    # the Honeybadger Heroku addon — they never pass through this Ruby
    # callback. Suppress them in the Honeybadger project dashboard
    # (Settings → Heroku integration / Insights filters), not here.
  end
end
