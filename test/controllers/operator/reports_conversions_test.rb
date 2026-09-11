require "test_helper"

class Operator::ReportsConversionsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
  end

  test "admin sees the conversions page with channel rows and a people drill-down" do
    log_in users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      Conversion.create!(operator: @operator, location: @location, user: @member, kind: "day_pass",
                         occurred_at: 1.day.ago, amount_cents: 3500, channel: "organic_search", surface: "web")
    end
    @member.update_columns(acquisition_channel: "organic_search", acquired_at: 3.days.ago, original_location_id: @location.id)

    get conversions_reports_path(period: "30d"), env: default_env
    assert_response :success
    assert_select "h4", text: "Conversions"
    assert_select "td a", text: "Organic search"
    assert_select "td", text: "$35"

    get conversions_reports_path(period: "30d", channel: "organic_search"), env: default_env
    assert_response :success
    assert_select "h6", text: /People from Organic search/
    assert_select "a[href=?]", user_path(@member)
  end

  test "members cannot open the conversions page" do
    log_in @member
    get conversions_reports_path, env: default_env
    assert_response :redirect
  end
end
