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
end
