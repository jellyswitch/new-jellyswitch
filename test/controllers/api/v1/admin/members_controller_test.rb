require "test_helper"

# Coverage for /api/v1/admin/members/:id/reservations — the endpoint the
# mobile admin's "Member Detail → Reservations" expandable section calls.
#
# Previously the JSON omitted `ended_early`, so a member who tapped
# "End reservation now" looked identical to a still-active booking in
# the admin's list. Staff couldn't tell whether the room was actually
# still occupied. This test locks in the field.
class Api::V1::Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)

    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
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

  test "reservations response includes ended_early so admins can badge it" do
    reservations(:room_reservation).update!(ended_early: true)

    get "/api/v1/admin/members/#{@member.id}/reservations", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation).id }
    refute_nil match, "expected the ended-early reservation in the response"
    assert_equal true, match["ended_early"],
      "ended_early must be surfaced or the admin list can't distinguish from active bookings"
  end

  test "reservations response includes ended_early=false for normal bookings" do
    reservations(:room_reservation).update!(ended_early: false)

    get "/api/v1/admin/members/#{@member.id}/reservations", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation).id }
    refute_nil match
    assert_equal false, match["ended_early"]
  end

  # #6: a member's past chat threads (with replies) on their admin page.
  test "conversations returns the member's feedback threads with replies inline" do
    feedback = MemberFeedback.create!(
      operator: @operator, user: @member, comment: "AC is too cold in the lounge",
    )
    feedback.feedback_replies.create!(
      operator: @operator, user: @admin, body: "Thanks — bumped the thermostat 2°.",
    )
    # A thread from a DIFFERENT member must not leak into this member's page.
    other = users(:cowork_tahoe_non_member)
    MemberFeedback.create!(operator: @operator, user: other, comment: "Where's the printer?")

    get "/api/v1/admin/members/#{@member.id}/conversations", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    ids  = body.map { |c| c["id"] }
    assert_includes ids, feedback.id
    refute_includes body.map { |c| c["body"] }, "Where's the printer?",
      "another member's thread must not appear on this member's page"

    thread = body.find { |c| c["id"] == feedback.id }
    assert_equal "AC is too cold in the lounge", thread["body"]
    assert_equal 1, thread["replies"].length
    assert_equal "Thanks — bumped the thermostat 2°.", thread["replies"].first["body"]
    assert_equal true, thread["replies"].first["is_admin"]
  end

  # "Recent" hides door-punch noise (keeps only the first after each
  # join/payment); the dedicated "doors" tab shows the full history.
  test "activities: recent hides door-punch noise, doors tab shows all" do
    @member.activities.delete_all
    t = Time.utc(2026, 1, 1, 9, 0)
    Activity.create!(user: @member, operator: @operator, kind: "subscription_started", occurred_at: t)
    milestone = Activity.create!(user: @member, operator: @operator, kind: "door_punch", occurred_at: t + 1.hour)
    noise     = Activity.create!(user: @member, operator: @operator, kind: "door_punch", occurred_at: t + 2.hours)

    get "/api/v1/admin/members/#{@member.id}/activities", params: { tab: "recent" }, headers: headers
    assert_response :success
    recent_ids = JSON.parse(response.body)["activities"].map { |a| a["id"] }
    assert_includes recent_ids, milestone.id
    refute_includes recent_ids, noise.id, "non-milestone door punch should be hidden from Recent"

    get "/api/v1/admin/members/#{@member.id}/activities", params: { tab: "doors" }, headers: headers
    assert_response :success
    doors = JSON.parse(response.body)["activities"].map { |a| a["id"] }
    assert_includes doors, milestone.id
    assert_includes doors, noise.id
    assert_equal [milestone.id, noise.id].sort, doors.sort, "doors tab shows every door punch"
  end
end
