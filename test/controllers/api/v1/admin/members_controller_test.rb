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

  # Auth as an arbitrary staff user (for the role-grant authorization tests).
  def headers_for(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  # ---- role-grant authorization (privilege-escalation fix) ----------------

  test "community manager cannot escalate a member to superadmin" do
    cm     = users(:cowork_tahoe_community_manager)
    member = users(:cowork_tahoe_member)

    patch "/api/v1/admin/members/#{member.id}",
          params: { role: "superadmin" }.to_json, headers: headers_for(cm)

    assert_response :forbidden
    assert_equal "unassigned", member.reload.role, "role must not change on a forbidden grant"
  end

  test "general manager cannot grant admin" do
    gm     = users(:cowork_tahoe_general_manager)
    member = users(:cowork_tahoe_member)

    patch "/api/v1/admin/members/#{member.id}",
          params: { role: "admin" }.to_json, headers: headers_for(gm)

    assert_response :forbidden
    assert_equal "unassigned", member.reload.role
  end

  test "superadmin can grant superadmin" do
    superadmin = users(:cowork_tahoe_superadmin)
    member     = users(:cowork_tahoe_member)

    patch "/api/v1/admin/members/#{member.id}",
          params: { role: "superadmin" }.to_json, headers: headers_for(superadmin)

    assert_response :success
    assert_equal "superadmin", member.reload.role
  end

  test "ordinary profile edits still work and never change role" do
    cm     = users(:cowork_tahoe_community_manager)
    member = users(:cowork_tahoe_member)

    patch "/api/v1/admin/members/#{member.id}",
          params: { name: "Renamed Member" }.to_json, headers: headers_for(cm)

    assert_response :success
    member.reload
    assert_equal "Renamed Member", member.name
    assert_equal "unassigned", member.role
  end

  test "resubmitting a higher-role target's unchanged role is allowed" do
    # A GM editing an admin's phone: the payload echoes role: admin (which a GM
    # could never GRANT), but it's unchanged, so the edit must not be blocked.
    gm    = users(:cowork_tahoe_general_manager)
    admin = users(:cowork_tahoe_admin)

    patch "/api/v1/admin/members/#{admin.id}",
          params: { phone: "5305550123", role: "admin" }.to_json, headers: headers_for(gm)

    assert_response :success
    assert_equal "admin", admin.reload.role
  end

  test "create cannot mint a superadmin from a community manager" do
    cm = users(:cowork_tahoe_community_manager)

    assert_no_difference -> { User.where(role: "superadmin").count } do
      post "/api/v1/admin/members",
           params: { name: "X", email: "x-escalate@example.com", phone: "5305550000",
                     password: "secret123", role: "superadmin" }.to_json,
           headers: headers_for(cm)
    end
    assert_response :forbidden
  end

  test "role column rejects unknown values (defense in depth)" do
    member = users(:cowork_tahoe_member)
    member.role = "wizard"
    refute member.valid?, "an unknown role must be invalid"
    assert_includes member.errors[:role], "is not included in the list"
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

  test "conversations flags dismissed threads so clients can offer Restore" do
    live      = MemberFeedback.create!(operator: @operator, user: @member, comment: "Live thread")
    dismissed = MemberFeedback.create!(operator: @operator, user: @member, comment: "Old thread",
      dismissed_at: Time.current)

    get "/api/v1/admin/members/#{@member.id}/conversations", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal false, body.find { |c| c["id"] == live.id }["dismissed"]
    assert_equal true,  body.find { |c| c["id"] == dismissed.id }["dismissed"]
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

  # --- Group (organization) info + assignment ---

  test "show includes the member's group id, name, and owner flag" do
    org = organizations(:sierra_nevada_organization)
    @member.update!(organization: org)

    get "/api/v1/admin/members/#{@member.id}", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal org.id, body["organization_id"]
    assert_equal org.name, body["organization_name"]
    assert_equal org.owner_id == @member.id, body["organization_owner"]
    assert_includes body.keys, "always_allow_building_access"
  end

  test "assign_organization puts the member in the group" do
    org = organizations(:sierra_nevada_organization)
    @member.update!(organization: nil)

    post "/api/v1/admin/members/#{@member.id}/assign_organization",
         params: { organization_id: org.id }.to_json, headers: headers
    assert_response :success

    assert_equal org.id, @member.reload.organization_id
    assert_equal org.name, JSON.parse(response.body)["organization_name"]
  end

  test "assign_organization 404s for a group outside the tenant" do
    @member.update!(organization: nil)

    post "/api/v1/admin/members/#{@member.id}/assign_organization",
         params: { organization_id: 999_999 }.to_json, headers: headers
    assert_response :not_found

    assert_nil @member.reload.organization_id
  end

  test "remove_organization clears the group and bill_to_organization" do
    @member.update!(organization: organizations(:sierra_nevada_organization), bill_to_organization: true)

    post "/api/v1/admin/members/#{@member.id}/remove_organization", headers: headers
    assert_response :success

    @member.reload
    assert_nil @member.organization_id
    assert_equal false, @member.bill_to_organization
  end

  # Staff comp a room on the house: comp: true books the member without
  # capturing a charge — even on a priced room with a production operator.
  # (Without comp, this same booking would enter the Stripe charge path.)
  test "create_reservation with comp books a priced room free of charge" do
    @operator.update!(billing_state: "production")
    room = rooms(:small_meeting_room)
    room.update!(hourly_rate_in_cents: 5000)

    assert_difference -> { Reservation.count }, 1 do
      assert_no_difference -> { Invoice.count } do
        post "/api/v1/admin/members/#{@member.id}/create_reservation",
          params: {
            room_id: room.id,
            datetime_in: (Time.current + 10.days).iso8601,
            minutes: 60,
            comp: true,
          }.to_json,
          headers: headers
      end
    end

    assert_response :created
    reservation = Reservation.order(:created_at).last
    assert_equal @member.id, reservation.user_id
    assert_nil reservation.captured_at, "a comped booking must not capture a charge"
  end

  # The mobile "Add a Day Pass" action can schedule a comp for a future date —
  # the endpoint honors params[:date] rather than assuming today.
  test "create_day_pass books a free pass on a future date" do
    # Date handling is under test, not billing — stub the Stripe invoice steps
    # (same pattern as day_pass_access_test; the fixture location has no keys).
    Billing::DayPasses::CreateStripeInvoice.stubs(:call!) { |context| context }
    Billing::DayPasses::ChargeDayPassInvoice.stubs(:call!) { |context| context }

    free_type = DayPassType.create!(
      operator: @operator, location: locations(:cowork_tahoe_location),
      name: "Comp Pass", amount_in_cents: 0, available: true,
    )
    future = 5.days.from_now.to_date

    post "/api/v1/admin/members/#{@member.id}/create_day_pass",
      params: { day_pass_type_id: free_type.id, date: future.iso8601 }.to_json,
      headers: headers

    assert_response :created
    day_pass = DayPass.order(:created_at).last
    assert_equal @member.id, day_pass.user_id
    assert_equal future, day_pass.day
  end

  test "create_day_pass with comp mints a paid pass without invoicing" do
    Stripe::InvoiceItem.expects(:create).never
    Stripe::Invoice.expects(:create).never
    paid_type = DayPassType.create!(
      operator: @operator, location: locations(:cowork_tahoe_location),
      name: "Private Office Day Pass", amount_in_cents: 10000, available: true,
    )

    post "/api/v1/admin/members/#{@member.id}/create_day_pass",
      params: { day_pass_type_id: paid_type.id, comp: true }.to_json,
      headers: headers

    assert_response :created
    day_pass = DayPass.order(:created_at).last
    assert_equal @member.id, day_pass.user_id
    assert_equal paid_type, day_pass.day_pass_type
    assert day_pass.complimentary?
    assert_nil day_pass.invoice_id
  end

  test "usage reports visit_days derived from collected activity" do
    @member.checkins.destroy_all
    door = Door.create!(name: "Front Door", operator: @operator,
                        location: locations(:cowork_tahoe_location), available: true)
    DoorPunch.create!(user: @member, door: door, operator: @operator)

    get "/api/v1/admin/members/#{@member.id}/usage", headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("visit_days"), "usage JSON is missing visit_days"
    assert_operator body["visit_days"], :>=, 1
  end
end
