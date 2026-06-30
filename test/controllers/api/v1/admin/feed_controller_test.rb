require "test_helper"

# Coverage for the admin feed serializer's reservation charge amount
# (GET /api/v1/admin/feed).
#
# A 'reservation' feed card used to derive its amount from
# room.hourly_rate_in_cents, which is $0 for free meeting rooms — so a
# day-passer who exceeded their included meeting-room minutes on a free room
# showed $0 in the admin feed even though they were charged an overage. The
# amount now reflects the actual charge (captured / authorized / computed).
class Api::V1::Admin::FeedControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    # 'reservation' cards are filtered out unless the operator opts in.
    @operator.update!(reservation_notifications: true)
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

  def feed_item_for(reservation, user)
    FeedItem.create!(
      operator: @operator,
      location: @location,
      user: user,
      blob: { "type" => "reservation", "reservation_id" => reservation.id, "user_name" => user.name },
    )
  end

  def fetch_item(feed_item)
    get "/api/v1/admin/feed", headers: headers
    assert_response :success
    JSON.parse(response.body).find { |i| i["id"] == feed_item.id }
  end

  test "day-pass overage on a free room shows the overage charge, not $0" do
    feed_item = nil
    expected_cents = 6000 # 120 min used − 60 included = 60 min over; $60/hr overage

    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room   = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      dpt    = create(:day_pass_type, operator: @operator, location: @location,
                      included_meeting_room_minutes: 60, overage_rate_in_cents: 6000)
      reservation = create(:reservation, user: member, room: room, minutes: 120, paid: true)
      create(:day_pass, user: member, billable: member, day: reservation.datetime_in.to_date,
             day_pass_type: dpt, operator: @operator, location: @location)

      assert_nil reservation.captured_amount_in_cents
      assert_nil reservation.authorized_amount_in_cents

      feed_item = feed_item_for(reservation, member)
    end

    item = fetch_item(feed_item)
    assert item, "reservation feed item should be present"
    assert_equal expected_cents, item["amount"]
  end

  test "captured amount wins over the computed estimate" do
    feed_item = nil

    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room   = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      reservation = create(:reservation, user: member, room: room, minutes: 120, paid: true,
                           captured_amount_in_cents: 4200)
      feed_item = feed_item_for(reservation, member)
    end

    item = fetch_item(feed_item)
    assert_equal 4200, item["amount"]
  end

  test "free reservation shows no charge" do
    feed_item = nil

    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room   = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      reservation = create(:reservation, user: member, room: room, minutes: 30, paid: false)
      feed_item = feed_item_for(reservation, member)
    end

    item = fetch_item(feed_item)
    assert item
    assert_nil item["amount"]
  end

  test "paid-room-reservation card shows the full live charge, not a stale snapshot" do
    @operator.update!(paid_room_reservation_notifications: true)
    feed_item = nil

    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room   = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 4000) # $40/hr
      # 3-hour booking → full charge is $120. A stale one-hour snapshot is $40.
      reservation = create(:reservation, user: member, room: room, minutes: 180, paid: true)

      feed_item = FeedItem.create!(
        operator: @operator, location: @location, user: member,
        blob: {
          "type" => "paid-room-reservation",
          "reservation_id" => reservation.id,
          "user_name" => member.name,
          "charge_amount_in_cents" => 4000, # stale snapshot from booking time
        },
      )
    end

    item = fetch_item(feed_item)
    assert item, "paid-room-reservation feed item should be present"
    assert_equal 12000, item["amount"] # full duration, not the $40 snapshot
  end

  def weekly_update_card(blob_overrides = {})
    feed_item = nil
    ActsAsTenant.with_tenant(@operator) do
      wu = WeeklyUpdate.create!(
        operator: @operator, location: @location,
        week_start: Time.current.beginning_of_week - 1.week,
        week_end: Time.current.end_of_week - 1.week,
        blob: {
          "day_passes" => 3, "checkins" => 7, "new_active_members" => 2,
          "revenue" => 500.0, "reservations" => 10,
          "paid_reservations" => 4, "member_reservations" => 6,
        }.merge(blob_overrides),
      )
      feed_item = FeedItem.create!(
        operator: @operator, location: @location, user: @admin,
        blob: { "type" => "weekly-update", "weekly_update_id" => wu.id },
      )
    end
    fetch_item(feed_item)["body"]
  end

  test "weekly-update revenue is shown in real dollars, not divided by 100 twice" do
    @location.update!(allow_hourly: true)
    body = weekly_update_card
    assert_includes body, "Revenue: $500" # was "$5" before the fix
  end

  test "weekly-update splits paid vs member reservations" do
    body = weekly_update_card
    assert_includes body, "Paid reservations: 4"
    assert_includes body, "Member reservations: 6"
    refute_includes body, "Reservations: 10" # the single total line is replaced
  end

  test "weekly-update hides check-ins when hourly access is disabled" do
    @location.update!(allow_hourly: false)
    body = weekly_update_card
    refute_includes body, "Check-ins:"
  end

  test "weekly-update shows check-ins when hourly access is enabled" do
    @location.update!(allow_hourly: true)
    body = weekly_update_card
    assert_includes body, "Check-ins: 7"
  end

  test "note body decodes HTML entities and keeps line breaks (web/mobile parity)" do
    @operator.update!(post_notifications: true)
    feed_item = nil

    ActsAsTenant.with_tenant(@operator) do
      feed_item = FeedItem.create!(
        operator: @operator, location: @location, user: @admin,
        # The full rich text is what the web renders correctly.
        text: "<div>Dailies &amp; walk (checked conf rooms)</div><div>Unpacked snacks</div>",
        # The legacy strip_tags value: entities encoded, no line breaks.
        blob: { "type" => "post", "text" => "Dailies &amp; walk (checked conf rooms)Unpacked snacks" },
      )
    end

    body = fetch_item(feed_item)["body"]
    assert_equal "Dailies & walk (checked conf rooms)\nUnpacked snacks", body
    refute_includes body, "&amp;"
  end

  # The @mention source for mobile notes. Mobile used to build this list by
  # filtering the first page of /admin/members down to admin roles, so admins
  # past page 1 — and all members — were invisible ("tagging admins broken").
  # The endpoint returns staff + approved members directly.
  test "GET mentionable_users returns staff and approved members" do
    get "/api/v1/admin/feed/mentionable_users", headers: headers
    assert_response :success

    body  = JSON.parse(response.body)
    names = body.map { |u| u["name"] }

    assert_includes names, "Dave Paola",        "admin should be returned"
    assert_includes names, "Community Manager", "CM should be returned"
    assert_includes names, "Tim C",             "approved member should be returned (#4)"
    assert body.all? { |u| u.key?("id") && u.key?("name") && u.key?("role") }, "shape has id/name/role"
  end

  # When a member replies in an existing feedback thread, the reply upserts the
  # thread's single feed card and bumps its updated_at (so it floats to the top
  # of the activity feed). The mobile feed used to order by created_at, leaving
  # the freshly-replied card buried at the conversation's original position —
  # "replies aren't showing at the top of the feed." It must order by recent
  # activity (updated_at), matching the web dashboard.
  test "feed orders by recent activity so a freshly-replied card floats to the top" do
    @operator.update!(member_feedback_notifications: true)
    bumped = nil
    newer_created = nil

    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)

      # An OLD thread whose conversation just received a new reply: old
      # created_at, but updated_at bumped to "now" by the reply upsert.
      bumped = FeedItem.create!(
        operator: @operator, location: @location, user: member,
        blob: { "type" => "feedback", "member_feedback_id" => 1, "body" => "older thread, just replied" },
        created_at: 3.days.ago, updated_at: 5.seconds.ago,
      )

      # A thread created AFTER the bumped one was first created, but with no
      # new activity since — its created_at is newer, its updated_at is older.
      newer_created = FeedItem.create!(
        operator: @operator, location: @location, user: member,
        blob: { "type" => "feedback", "member_feedback_id" => 2, "body" => "newer thread, no new replies" },
        created_at: 1.hour.ago, updated_at: 1.hour.ago,
      )
    end

    get "/api/v1/admin/feed", headers: headers
    assert_response :success
    ids = JSON.parse(response.body).map { |i| i["id"] }

    assert_includes ids, bumped.id
    assert_includes ids, newer_created.id
    assert ids.index(bumped.id) < ids.index(newer_created.id),
      "a freshly-replied (updated_at-bumped) card must sort above a more-recently-created but inactive one"
  end
end
