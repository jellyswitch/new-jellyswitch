require "test_helper"

# Day-pass building access honors the location's posted hours (Nash incident,
# 2026-08-07: a 1:34 AM pass purchase opened the lobby at 1:38 AM). A pass
# covers the DAY; the door only opens while the location is open. A pass TYPE
# flagged always_allow_building_access keeps 24/7 access, membership tiers keep
# their own logic (all_hours plans unlock any time), and a reservation's
# ±window (ADR 0013) is unchanged — a booking is its own access grant.
class Api::V1::DoorsHoursTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    # Pin the test dates BEFORE any travel_to — a dynamic helper would
    # recompute relative to the frozen clock and drift by a week.
    @tuesday  = Date.current.next_occurring(:tuesday) + 7
    @saturday = Date.current.next_occurring(:saturday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false)
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     amount_in_cents: 4000, always_allow_building_access: false)
      @allday_type = create(:day_pass_type, operator: @operator, location: @location,
                            amount_in_cents: 4000, always_allow_building_access: true)
    end
    @door = Door.create!(
      name: "Hours Gate Door", slug: "hours-door-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99077, available: true,
    )
    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status: 200,
      body: { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def grant_pass(user, day, type = @type)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass, user: user, billable: user, operator: @operator,
             location: @location, day_pass_type: type, day: day)
    end
  end

  def listed_door_ids(user)
    get "/api/v1/doors", headers: headers(user)
    assert_response :success
    JSON.parse(response.body).map { |d| d["id"] }
  end

  test "day pass opens the door during posted hours" do
    travel_to @zone.parse("#{@tuesday} 10:00") do
      grant_pass(@guest, @tuesday)
      assert_includes listed_door_ids(@guest), @door.id
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "day pass does NOT open the door at 2 AM" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      grant_pass(@guest, @tuesday)
      assert_equal [], listed_door_ids(@guest)
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :forbidden
      assert_not_requested :post, @kisi_url
    end
  end

  test "day pass still opens the door on a Saturday within posted hours" do
    # Weekend daytime day-pass entry is established behavior (prod audit
    # 2026-08-07) — only the TIME-of-day window bounds access, not the
    # open_<day> staffed-days flags.
    travel_to @zone.parse("#{@saturday} 10:00") do
      grant_pass(@guest, @saturday)
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
    end
  end

  test "always-allow pass type keeps 24/7 access" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      grant_pass(@guest, @tuesday, @allday_type)
      assert_includes listed_door_ids(@guest), @door.id
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
    end
  end

  test "bundle holder is bounded to posted hours" do
    ActsAsTenant.with_tenant(@operator) do
      DayPassBundle.create!(user: @guest, operator: @operator, location: @location,
                            day_pass_type: @type, quantity_purchased: 5,
                            passes_remaining: 5, purchased_at: Time.current)
    end
    travel_to @zone.parse("#{@tuesday} 02:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :forbidden
    end
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
    end
  end

  test "member on an all-hours plan still unlocks at 2 AM" do
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id, building_access_level: :all_hours)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(users(:cowork_tahoe_member))
      assert_response :success
    end
  end

  test "a reservation inside its access window still admits at 2 AM (ADR 0013 unchanged)" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      room = ActsAsTenant.with_tenant(@operator) do
        create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, rentable: true)
      end
      Reservation.new(user: @guest, room: room,
                      datetime_in: 30.minutes.from_now, minutes: 60).save!(validate: false)
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
    end
  end
end
