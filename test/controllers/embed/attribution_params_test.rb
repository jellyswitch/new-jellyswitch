require "test_helper"

# The one-line embeds (concierge launcher, showcase) carry the host page's
# campaign tags / ad click IDs / referrer into the Jellyswitch request so the
# visit is credited to the real source (Data › Conversions).
class Embed::AttributionParamsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @operator.update!(concierge_enabled: true, showcase_enabled: true)
    @location = @operator.locations.first
    @location.update!(visible: true)
    Rails.cache.clear
  end

  test "concierge launcher opens the widget with attribution params appended" do
    get embed_concierge_launcher_path(operator_subdomain: @operator.subdomain)
    assert_response :success
    assert_includes response.body, "function jswAttributionParams"
    assert_includes response.body, "frame.src = jswWithAttribution(WIDGET_URL)"
    assert_includes response.body, "jsw_ref="
  end

  test "showcase CTAs to Jellyswitch are decorated, link-out cards are not" do
    get embed_showcase_path(operator_subdomain: @operator.subdomain, location_id: @location.id, format: :js)
    assert_response :success
    assert_includes response.body, "function jswAttributionParams"
    assert_includes response.body, "cta.href = tier.external ? tier.cta : jswWithAttribution(tier.cta)"
  end
end
