require "test_helper"

# POST /api/v1/day_passes/redeem_today — Task 10 / ADR 0026: a Day Office
# bundle must route through Billing::DayPassBundles::ScheduleDay (allocates a
# pool room) instead of ConsumeOnEntry, which never allocates. Standard
# bundles keep the original ConsumeOnEntry path, untouched. Mirrors
# Operator::DayPassRedeemTodayTest (the web equivalent, ConsumeOnEntry-only).
class Api::V1::DayPassesRedeemTodayTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_non_member) # no sub / lease / reservation / day pass
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # make_office_bundle lives in test/day_office_helper.rb (DayOfficeHelper).

  test "redeeming a Day Office bundle allocates a room and returns a confirmation note" do
    bundle, room_a, = ActsAsTenant.with_tenant(@operator) { make_office_bundle }

    assert_difference -> { DayPass.where(user: @member, location: @location, day: Date.current).count }, 1 do
      post "/api/v1/day_passes/redeem_today", headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "redeemed", body["status"]
    assert_equal 4, bundle.reload.passes_remaining

    pass = DayPass.where(user: @member, location: @location, day: Date.current).first
    hold = pass.office_hold
    assert_equal room_a, hold.room
    assert_equal "#{hold.room.name} is yours #{hold.window_label}.", body["confirmation_note"]
  end

  test "redeeming a Day Office bundle with a sold-out pool returns the structured sold-out payload" do
    std = nil
    ActsAsTenant.with_tenant(@operator) do
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Office Pack",
                                amount_in_cents: 20000, quantity: 5, kind: "day_office",
                                included_meeting_room_minutes: 0, available: true, visible: true)
      # No rooms assigned to the pool — any allocation attempt is sold out.
      DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      # Deterministic fallback (mirrors Api::V1::DayPassesControllerTest's
      # @std) — default_for_room_booking wins outright over the
      # cheapest-tiebreak branch, so this is unambiguously "the" fallback.
      std = DayPassType.create!(name: "Standard Fallback", operator: @operator, location: @location,
                                kind: "standard", amount_in_cents: 5000, available: true, visible: true,
                                default_for_room_booking: true)
    end

    assert_no_difference -> { DayPass.count } do
      post "/api/v1/day_passes/redeem_today", headers: headers
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert_equal std.id, body.dig("fallback_day_pass_type", "id")
  end

  # Quality-review fix 1 pin (ScheduleDay#eligible_bundle): the "must survive
  # until end of day" expiry filter must NOT apply to a same-day (today)
  # schedule — only .active's own "not expired right now" check should. A
  # bundle expiring LATER TODAY must still be redeemable today. Frozen to a
  # deterministic mid-morning instant so this can never collide with the
  # bundle's own end-of-day expiry regardless of when the suite actually runs.
  test "a Day Office bundle expiring later today can still be redeemed today" do
    zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    wednesday = Date.current.next_occurring(:wednesday) + 7
    bundle = room_a = nil

    travel_to zone.parse("#{wednesday} 10:00") do
      ActsAsTenant.with_tenant(@operator) do
        bundle, room_a, = make_office_bundle
        bundle.update!(expires_at: zone.parse("#{wednesday} 23:00")) # later today, before midnight
      end

      assert_difference -> { DayPass.where(user: @member, location: @location, day: wednesday).count }, 1 do
        post "/api/v1/day_passes/redeem_today", headers: headers
      end

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "redeemed", body["status"]
      assert body["confirmation_note"].present?
      pass = DayPass.where(user: @member, location: @location, day: wednesday).first
      assert_equal room_a, pass.office_hold&.room
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  # Quality-review fix 2 pin: redeem_today's routing lookup and ScheduleDay's
  # internal draw must agree on which bundle is "the" active one for today —
  # otherwise routing can send the request down the office path while the
  # interactor actually draws (and burns) a DIFFERENT bundle, or send it down
  # the standard path while an office bundle sits there unused. draw_order
  # sorts by soonest REAL expiry first, NULLs/perpetual LAST regardless of
  # creation order (proved by ScheduleDayTest's "draws from the
  # soonest-expiring bundle first") — so the office bundle here is given the
  # sooner concrete expiry, even though the standard bundle is the OLDER
  # (created first, lower id) one that a plain unordered `.first` would have
  # picked instead.
  test "with two active bundles, redeem_today's routing agrees with ScheduleDay's draw" do
    standard_bundle = do_bundle = room_a = nil
    ActsAsTenant.with_tenant(@operator) do
      standard_dpt = DayPassType.create!(operator: @operator, location: @location, name: "Standard Pack",
                                         amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      standard_bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                              day_pass_type: standard_dpt, quantity_purchased: 5,
                                              passes_remaining: 5, purchased_at: Time.current) # perpetual, created first

      do_bundle, room_a, = make_office_bundle
      do_bundle.update!(expires_at: 5.days.from_now) # real, soon expiry — outranks perpetual under draw_order
    end

    assert_difference -> { DayPass.where(user: @member, location: @location, day: Date.current).count }, 1 do
      post "/api/v1/day_passes/redeem_today", headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "redeemed", body["status"]
    assert body["confirmation_note"].present?, "must have routed to (and drawn) the office bundle"

    pass = DayPass.where(user: @member, location: @location, day: Date.current).first
    assert_equal room_a, pass.office_hold&.room
    assert_equal 4, do_bundle.reload.passes_remaining, "the office bundle must be the one burned"
    assert_equal 5, standard_bundle.reload.passes_remaining, "the standard bundle must be untouched"
  end

  test "redeeming a standard bundle is unaffected: burns one pass via ConsumeOnEntry" do
    bundle = nil
    ActsAsTenant.with_tenant(@operator) do
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "Standard Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                                     quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
    end

    assert_difference -> { DayPass.where(user: @member, location: @location, day: Date.current).count }, 1 do
      post "/api/v1/day_passes/redeem_today", headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "redeemed", body["status"]
    assert_equal 4, bundle.reload.passes_remaining
    assert_not body.key?("confirmation_note"), "the standard path's response shape is unchanged"
  end
end
