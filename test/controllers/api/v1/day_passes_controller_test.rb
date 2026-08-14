require "test_helper"
require "stripe_mock"

# T8: the Day Office API contract (ADR 0026) — #types exposes `kind`,
# #create/#index carry the office hold's room + a human window label, and a
# sold-out Day Office purchase (whether caught by the pre-check gate or lost
# in an allocation race that only surfaces once the purchase organizer
# actually runs) returns a structured, machine-readable payload with a
# suggested standard-type fallback. Also covers the T5 review fold-in:
# #create's type lookup must be location-scoped, not just tenant-scoped.
class Api::V1::DayPassesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @other    = users(:cowork_tahoe_non_member)
    @day      = Date.current + 7

    @type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                kind: "day_office", amount_in_cents: 7500,
                                included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "B", operator: @operator, location: @location)
    @type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })

    # Deterministic fallback: fixtures already give this operator an
    # available+visible $200 standard type (day_pass_type.yml), but
    # default_for_room_booking: true wins outright over
    # suggested_standard_for's cheapest-tiebreak branch — so this is
    # unambiguously "the" fallback no matter what else exists.
    @std = DayPassType.create!(name: "Standard Fallback", operator: @operator, location: @location,
                               kind: "standard", amount_in_cents: 5000, available: true, visible: true,
                               default_for_room_booking: true)
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # Books every pool room solid for the whole posted-hours span on `day`, so
  # DayOffices::Allocator has nothing free to hand out. Mirrors
  # Billing::DayPasses::AllocateDayOfficeTest#fill_pool!.
  def fill_all_pool_rooms!(day = @day)
    span = @location.posted_hours_span(day)
    [@room_a, @room_b].each do |room|
      Reservation.create!(user: @other, room: room, datetime_in: span.first, minutes: 600)
    end
  end

  # Gives `user` a real (StripeMock) customer + attached card for @location,
  # so ChargeDayPassInvoice finds a payment method to charge. Mirrors
  # Billing::DayPasses::AllocateDayOfficeTest#attach_card!.
  def attach_card!(user)
    token = StripeMock.create_test_helper.generate_card_token
    customer = Stripe::Customer.create(
      { email: user.email, source: token },
      { api_key: @location.stripe_secret_key, stripe_account: @location.stripe_user_id }
    )
    user.update_stripe_customer_id_for_location(@location, customer.id)
    user.update_card_added_for_location(@location, true)
  end

  # --- #types ----------------------------------------------------------

  test "types payload carries kind for both standard and day_office types" do
    get "/api/v1/day_pass_types", headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "day_office", body.find { |t| t["id"] == @type.id }["kind"]
    assert_equal "standard", body.find { |t| t["id"] == @std.id }["kind"]
  end

  # --- #create: location scoping (T5 fold-in) ---------------------------

  test "a day pass type belonging to another location 404s instead of purchasing" do
    other_location = Location.create!(operator: @operator, name: "Other Location")
    cross_type = DayPassType.create!(name: "Cross Location Pass", operator: @operator, location: other_location,
                                     amount_in_cents: 5000, available: true, visible: true)

    assert_no_difference -> { DayPass.count } do
      post "/api/v1/day_passes", params: { day_pass_type_id: cross_type.id, date: @day.iso8601 }, headers: headers
    end

    assert_response :not_found
    assert_equal "Not found", JSON.parse(response.body)["error"]
  end

  # --- #create: day-office sold-out pre-check -----------------------------

  test "sold-out office purchase returns a structured payload with a fallback" do
    fill_all_pool_rooms!

    assert_no_difference -> { DayPass.count } do
      post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert_includes body["error"], "fully booked"
    fallback = body["fallback_day_pass_type"]
    assert_equal @std.id, fallback["id"]
    assert_equal @std.name, fallback["name"]
    assert_equal @std.amount_in_cents, fallback["price"]
  end

  test "a sold-out rejection lands in the management feed once, even on retap" do
    fill_all_pool_rooms!
    sold_out_items = -> {
      FeedItem.unscoped.where(operator_id: @operator.id, user_id: @member.id)
              .where("blob->>'type' = ?", "day-office-sold-out")
    }

    assert_difference -> { sold_out_items.call.count }, 1 do
      post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end
    assert_response :unprocessable_entity

    item = sold_out_items.call.last
    assert_equal @day.iso8601, item.blob["day"]
    assert_includes item.blob["text"], "sold out"

    # Retapping the same sold-out day must not stack cards.
    assert_no_difference -> { sold_out_items.call.count } do
      post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end
    assert_response :unprocessable_entity
  end

  test "sold-out fallback is null when no standard type qualifies" do
    # Neutralize every OTHER qualifying standard type — the operator's
    # fixture standard type ($200, available+visible) would otherwise win
    # suggested_standard_for's cheapest-tiebreak branch once @std is gone.
    day_pass_type(:cowork_tahoe_day_pass_type).update!(available: false)
    @std.update!(available: false)
    fill_all_pool_rooms!

    post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert body.key?("fallback_day_pass_type")
    assert_nil body["fallback_day_pass_type"]
  end

  # --- #create: race backstop ---------------------------------------------

  test "an allocation race lost inside the organizer returns the same structured payload" do
    # The pool is genuinely free, so the pre-check gate (available_room)
    # passes normally — but the allocator itself is stubbed to lose the race
    # (allocate! returns nil), the same shape a real concurrent purchase
    # produces between the gate check and AllocateDayOffice's actual
    # reservation attempt. SaveDayPass must still succeed for the chain to
    # reach AllocateDayOffice at all, hence attach_card! — which itself needs
    # StripeMock started first (it mints the card token through it). No FCM
    # stub needed: AllocateDayOffice fails before CreateNotifications, later
    # in the organizer chain, ever runs.
    StripeMock.start
    attach_card!(@member)

    assert_no_difference -> { DayPass.count } do
      DayOffices::Allocator.stub :allocate!, nil do
        post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
      end
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert_equal @std.id, body.dig("fallback_day_pass_type", "id")
  end

  # --- #create + #index: success carries the office room -------------------

  test "a successful office purchase returns a confirmation note and the index carries the room" do
    StripeMock.start
    attach_card!(@member)
    stub_request(:post, "https://fcm.googleapis.com/fcm/send").to_return(status: 200)

    post "/api/v1/day_passes", params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers

    assert_response :created
    body = JSON.parse(response.body)
    assert body["success"]

    pass = DayPass.find(body["id"])
    hold = pass.office_hold
    assert_equal @room_a, hold.room
    assert_equal "#{hold.room.name} is yours #{hold.window_label}.", body["confirmation_note"]

    get "/api/v1/my_day_passes", headers: headers

    assert_response :success
    row = JSON.parse(response.body).find { |p| p["id"] == pass.id }
    assert_equal "A", row["office_room"]
    assert_equal hold.window_label, row["office_window"]
  end
end
