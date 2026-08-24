require "test_helper"

# The mobile admin feed (GET /api/v1/admin/feed) was operator-wide: it filtered
# by operator and never by location, while the web dashboard has always scoped
# to the admin's current location (FeedItemsHelper#generic_feed_items).
#
# For a multi-location operator that meant every admin saw every sibling
# location's activity. Untethered's Fulton, MO staff opened their app to a feed
# that was 27-of-30 Zephyr Cove items — the giveaway being Zephyr Cove's weekly
# update landing in Fulton's feed (reported 2026-08-24).
class Api::V1::Admin::FeedLocationScopeTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @here     = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)

    ActsAsTenant.with_tenant(@operator) do
      @there = Location.create!(
        name: "Sibling #{SecureRandom.hex(2)}",
        operator: @operator,
        visible: true,
        time_zone: "Central Time (US & Canada)",
        working_day_start: "09:00",
        working_day_end: "18:00",
      )
    end

    @admin.update!(original_location: @here, current_location: @here)

    @here_item    = note_at(@here,  "here")
    @there_item   = note_at(@there, "there")
    # Legacy rows predate location stamping; the web keeps showing them, so the
    # app must too.
    @legacy_item  = note_at(nil,    "legacy")
  end

  def note_at(location, body)
    FeedItem.create!(
      operator: @operator,
      location: location,
      user: @admin,
      blob: { "type" => "post", "body" => body, "text" => body, "user_name" => @admin.name },
    )
  end

  def headers
    token = JWT.encode(
      { user_id: @admin.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def feed_ids
    get "/api/v1/admin/feed", headers: headers
    assert_response :success
    JSON.parse(response.body).map { |i| i["id"] }
  end

  test "the feed shows this location's items and hides a sibling location's" do
    ids = feed_ids

    assert_includes ids, @here_item.id
    assert_not_includes ids, @there_item.id,
      "a sibling location's activity must not appear in this location's feed"
  end

  test "location-less legacy items stay visible, as on the web" do
    assert_includes feed_ids, @legacy_item.id
  end

  test "switching location in the app switches the feed" do
    # The Location Switch screen writes current_location. The API's shared
    # current_location helper resolves original_location FIRST, so reading that
    # would pin the feed to the admin's home location forever.
    @admin.update!(current_location: @there)
    ids = feed_ids

    assert_includes ids, @there_item.id
    assert_not_includes ids, @here_item.id
  end

  test "a note posted from the app lands at the location whose feed it was posted to" do
    @admin.update!(current_location: @there)

    post "/api/v1/admin/feed", params: { body: "posted from Fulton" }.to_json, headers: headers
    assert_response :created

    created = FeedItem.find(JSON.parse(response.body)["id"])
    assert_equal @there.id, created.location_id,
      "a note must land in the feed the admin was reading, or it vanishes on post"
    assert_includes feed_ids, created.id
  end

  test "a single-location operator's feed is unchanged" do
    assert_equal 1, @operator.locations.where.not(id: @there.id).count
    @admin.update!(current_location: @here)

    ids = feed_ids
    assert_includes ids, @here_item.id
    assert_includes ids, @legacy_item.id
  end
end
