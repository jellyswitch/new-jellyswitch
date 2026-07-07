require "test_helper"

# Coverage for GET /api/v1/announcements — the list the mobile member app shows.
#
# Announcements auto-archive from the member-facing list after
# Announcement::ACTIVE_WINDOW_DAYS days (measured from when they were posted),
# so members stop seeing stale posts. The records are retained (staff keep full
# visibility via the admin API); they just drop off the member list.
class Api::V1::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def announcement_at(created_at, body:)
    ActsAsTenant.with_tenant(@operator) do
      Announcement.create!(
        operator: @operator, location: @location, user: @member,
        body: body, created_at: created_at,
      )
    end
  end

  def index_ids
    get "/api/v1/announcements", headers: headers
    assert_response :success
    JSON.parse(response.body).map { |a| a["id"] }
  end

  test "shows announcements from the last 7 days and hides older ones" do
    fresh = announcement_at(6.days.ago, body: "fresh news")
    stale = announcement_at(8.days.ago, body: "old news")

    ids = index_ids
    assert_includes ids, fresh.id, "an announcement posted 6 days ago should still show"
    assert_not_includes ids, stale.id, "an announcement posted 8 days ago should be auto-archived"
  end

  test "only active announcements are returned when active and archived are mixed" do
    active = [announcement_at(1.day.ago, body: "a"), announcement_at(6.days.ago, body: "b")]
    announcement_at(10.days.ago, body: "c")
    announcement_at(30.days.ago, body: "d")

    ids = index_ids
    assert_equal active.map(&:id).sort, ids.sort
  end
end
