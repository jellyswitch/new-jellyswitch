require "test_helper"

# The legacy web door-open path (GET /doors/:slug/open) and the web Keys page
# honor the location's posted hours for day-pass and bundle access (ADR 0023),
# same as the api/v1 unlock, the web-XHR unlock, and the Keys-list predicate.
# A pass covers the DAY; the door only opens while the location is open. Pass
# TYPES flagged always_allow_building_access keep 24/7 access, membership
# tiers keep their own logic (all_hours plans unlock any time), and staff are
# unchanged. Mirrors test/controllers/api/v1/doors_hours_test.rb.
class Operator::DoorsOpenHoursTest < ActionDispatch::IntegrationTest
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
      name: "Web Hours Door", slug: "web-hours-door-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99078, available: true,
    )
    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status: 200,
      body: { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
    host! "#{@operator.subdomain}.example.com"
  end

  def grant_pass(user, day, type = @type)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass, user: user, billable: user, operator: @operator,
             location: @location, day_pass_type: type, day: day)
    end
  end

  def open_door!
    get "/doors/#{@door.slug}/open", env: default_env
  end

  def create_active_bundle(user, type = @type)
    ActsAsTenant.with_tenant(@operator) do
      DayPassBundle.create!(user: user, billable: user, operator: @operator,
                            location: @location, day_pass_type: type,
                            quantity_purchased: 5, passes_remaining: 5,
                            purchased_at: Time.current)
    end
  end

  test "day pass opens the web door path during posted hours" do
    travel_to @zone.parse("#{@tuesday} 10:00") do
      grant_pass(@guest, @tuesday)
      log_in @guest
      open_door!
      assert_response :redirect
      assert_requested :post, @kisi_url, times: 1
      assert_equal 1, DoorPunch.where(user: @guest, door: @door).count
    end
  end

  test "day pass does NOT open the web door path at 2 AM" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      grant_pass(@guest, @tuesday)
      log_in @guest
      open_door!
      assert_response :redirect
      assert_match(/not allowed/i, flash[:alert].to_s)
      assert_not_requested :post, @kisi_url
      assert_equal 0, DoorPunch.where(user: @guest, door: @door).count
    end
  end

  test "day pass still opens the web path on a Saturday within posted hours" do
    # Weekend daytime day-pass entry is established behavior (prod audit
    # 2026-08-07) — only the TIME-of-day window bounds access, not the
    # open_<day> staffed-days flags.
    travel_to @zone.parse("#{@saturday} 10:00") do
      grant_pass(@guest, @saturday)
      log_in @guest
      open_door!
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "always-allow pass type keeps 24/7 access on the web path" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      grant_pass(@guest, @tuesday, @allday_type)
      log_in @guest
      open_door!
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "bundle holder is bounded to posted hours and burns nothing outside them" do
    bundle = create_active_bundle(@guest)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      log_in @guest
      open_door!
      assert_not_requested :post, @kisi_url
      assert_equal 5, bundle.reload.passes_remaining, "denied entry must not burn a bundle day"
      assert_equal 0, DayPass.where(user: @guest).count
    end
    travel_to @zone.parse("#{@tuesday} 10:00") do
      open_door!
      assert_requested :post, @kisi_url, times: 1
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "always-allow bundle type keeps 24/7 access on the web path" do
    bundle = create_active_bundle(@guest, @allday_type)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      log_in @guest
      open_door!
      assert_requested :post, @kisi_url, times: 1
      assert_equal 4, bundle.reload.passes_remaining, "24/7 bundle entry still burns its day"
    end
  end

  test "member on an all-hours plan still opens at 2 AM" do
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id, building_access_level: :all_hours)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      log_in users(:cowork_tahoe_member)
      open_door!
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "staff still open at 2 AM" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      log_in users(:cowork_tahoe_admin)
      open_door!
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "web Keys page is bounded to posted hours for day-pass holders" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      grant_pass(@guest, @tuesday)
      log_in @guest
      get "/doors/keys", env: default_env
      assert_response :redirect
      assert_match(/not allowed/i, flash[:alert].to_s)
    end
    travel_to @zone.parse("#{@tuesday} 10:00") do
      get "/doors/keys", env: default_env
      assert_response :success
    end
  end
end
