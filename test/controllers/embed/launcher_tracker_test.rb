require "test_helper"

# The concierge launcher carries the site tracker (page-view beacon + link
# decoration) even when the chat bubble itself is switched off.
class Embed::LauncherTrackerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.locations.first.update!(visible: true)
    Rails.cache.clear
  end

  test "with concierge off the launcher is tracker-only" do
    @operator.update!(concierge_enabled: false)
    get embed_concierge_launcher_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_includes response.body, "navigator.sendBeacon"
    assert_includes response.body, embed_track_path(operator_subdomain: @operator.subdomain)
    assert_includes response.body, "__jswLinkDecorator"
    assert_includes response.body, "tracker only"
    assert_not_includes response.body, "jswcx-btn{position:fixed"
  end

  test "with concierge on the launcher has the tracker and the chat bubble" do
    @operator.update!(concierge_enabled: true)
    get embed_concierge_launcher_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_includes response.body, "navigator.sendBeacon"
    assert_includes response.body, "jswcx-btn{position:fixed"
    assert_includes response.body, "frame.src = jswWithAttribution(WIDGET_URL)"
  end
end
