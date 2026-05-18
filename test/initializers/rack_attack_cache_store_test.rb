require "test_helper"

# Rack::Attack defaults to Rails.cache. On Heroku, Rails.cache is FileStore,
# which is per-dyno — meaning throttle counters never sum across dynos and
# the rate limit silently no-ops in production. We override the store to use
# Redis (shared across dynos) when REDIS_URL is present.
class RackAttackCacheStoreTest < ActiveSupport::TestCase
  setup do
    @original_store = Rack::Attack.cache.store
    @original_redis_url = ENV["REDIS_URL"]
  end

  teardown do
    Rack::Attack.cache.store = @original_store
    if @original_redis_url
      ENV["REDIS_URL"] = @original_redis_url
    else
      ENV.delete("REDIS_URL")
    end
  end

  test "configures a Redis-backed cache store when REDIS_URL is set" do
    ENV["REDIS_URL"] = "redis://example.test:6379/0"

    RackAttackConfig.configure_cache_store!

    # Rack::Attack wraps the assigned store in a RedisCacheStoreProxy.
    assert_kind_of Rack::Attack::StoreProxy::RedisCacheStoreProxy, Rack::Attack.cache.store
  end

  test "leaves the default cache store alone when REDIS_URL is blank" do
    ENV.delete("REDIS_URL")
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    RackAttackConfig.configure_cache_store!

    assert_instance_of ActiveSupport::Cache::MemoryStore, Rack::Attack.cache.store
  end
end
