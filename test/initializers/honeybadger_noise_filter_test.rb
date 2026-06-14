require "test_helper"

# The Honeybadger before_notify callback suppresses exceptions that are
# expected business events or known transient infrastructure noise, so real
# bugs aren't buried (and our Honeybadger quota isn't burned). The decision
# logic lives in HoneybadgerNoiseFilter so it can be unit-tested directly
# instead of through the configure block.
class HoneybadgerNoiseFilterTest < ActiveSupport::TestCase
  # Minimal stand-in for a Honeybadger::Notice (only the bits the filter reads).
  Notice = Struct.new(:exception, :component, :action)

  def notice(exception, component: nil, action: nil)
    Notice.new(exception, component, action)
  end

  test "suppresses Stripe::CardError (handled + surfaced to the member)" do
    assert HoneybadgerNoiseFilter.suppress?(notice(Stripe::CardError.allocate))
  end

  test "suppresses empty-multipart bot probes" do
    assert HoneybadgerNoiseFilter.suppress?(notice(Rack::Multipart::EmptyContentError.new))
  end

  # Regression: RedisClient::ReadTimeoutError from the no-HA Mini Redis was
  # surfacing as a real error (Honeybadger #131696063, SendNotificationsJob)
  # because the old filter only enumerated Errno::ECONNRESET / SSLError.
  test "suppresses RedisClient read-timeout transients" do
    assert HoneybadgerNoiseFilter.suppress?(notice(RedisClient::ReadTimeoutError.new("Waited 5 seconds")))
  end

  test "suppresses any RedisClient connection transient (failover, cannot-connect, write timeout)" do
    [
      RedisClient::ConnectionError.new("connection reset"),
      RedisClient::CannotConnectError.new("cannot connect"),
      RedisClient::FailoverError.new("failover"),
      RedisClient::WriteTimeoutError.new("write timed out"),
    ].each do |ex|
      assert HoneybadgerNoiseFilter.suppress?(notice(ex)), "expected #{ex.class} to be suppressed"
    end
  end

  test "suppresses redis-rb connection transients (the $redis / TrafficControl path)" do
    assert HoneybadgerNoiseFilter.suppress?(notice(Redis::TimeoutError.new("timed out")))
    assert HoneybadgerNoiseFilter.suppress?(notice(Redis::CannotConnectError.new("cannot connect")))
  end

  # A RedisClient::CommandError is a REAL problem (e.g. OOM once the 25 MB
  # noeviction Redis fills, WRONGTYPE, etc.) — it must still alert us.
  test "does NOT suppress RedisClient::CommandError (real capacity/logic errors)" do
    refute HoneybadgerNoiseFilter.suppress?(notice(RedisClient::CommandError.new("OOM command not allowed")))
  end

  test "suppresses ECONNRESET only when it originates in the Redis client" do
    from_redis = Errno::ECONNRESET.new
    from_redis.set_backtrace(["/app/vendor/bundle/ruby/3.3.0/gems/redis-client-0.29.0/lib/redis_client.rb:123:in `call'"])
    assert HoneybadgerNoiseFilter.suppress?(notice(from_redis))

    elsewhere = Errno::ECONNRESET.new
    elsewhere.set_backtrace(["/app/app/services/some_outbound_http_call.rb:42:in `post'"])
    refute HoneybadgerNoiseFilter.suppress?(notice(elsewhere))
  end

  test "suppresses context-less at_exit noise from rails-runner one-liners" do
    assert HoneybadgerNoiseFilter.suppress?(notice(RuntimeError.new("typo"), component: "at_exit", action: nil))
  end

  test "does NOT suppress an ordinary application error" do
    refute HoneybadgerNoiseFilter.suppress?(notice(RuntimeError.new("a real bug")))
  end
end
