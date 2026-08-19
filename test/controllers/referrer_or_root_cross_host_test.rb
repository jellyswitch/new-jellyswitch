require "test_helper"

# Pundit's "Whoops, that's not allowed" handler bounces the visitor back to
# their referrer. Hopping between brands leaves a FOREIGN referrer (logged in
# on untethered.space, click into tml.jellyswitch.com, denied) — and a bare
# redirect_to a foreign host raises UnsafeRedirectError, turning the polite
# bounce into a 500 (Honeybadger, 2026-08-19, operator/feed_items#index).
class ReferrerOrRootCrossHostTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
    end
    host! "#{@operator.subdomain}.example.com"
  end

  test "a Pundit denial with a foreign-host referrer lands on root, not a 500" do
    log_in @member

    get "/feed_items", env: default_env.merge("HTTP_REFERER" => "https://untethered.space/")

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
  end

  test "a Pundit denial with a same-host referrer still bounces back there" do
    log_in @member

    get "/feed_items",
        env: default_env.merge("HTTP_REFERER" => "http://#{@operator.subdomain}.example.com/home")

    assert_response :redirect
    assert_equal "/home", URI.parse(response.location).path
  end

  test "a malformed referrer falls back to root" do
    log_in @member

    get "/feed_items", env: default_env.merge("HTTP_REFERER" => "http://[bad")

    assert_response :redirect
    assert_equal root_path, URI.parse(response.location).path
  end
end
