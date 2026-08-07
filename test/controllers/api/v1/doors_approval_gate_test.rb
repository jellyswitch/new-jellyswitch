require "test_helper"

# Approval is the HARD GATE for building access (David, 2026-08-08, after the
# Nash incident — an unapproved 1:19 AM signup bought a pass and opened the
# lobby at 1:38 AM). Screening happens BEFORE the door opens: an unapproved
# account gets no keys and no unlock regardless of day passes, bundles,
# memberships, leases, or reservations. Purchasing and booking stay
# self-serve (coverage-gated only) — the app keeps unapproved members on the
# Welcome/pending screen and staff approve from the members queue.
class Api::V1::DoorsApprovalGateTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @type = create(:day_pass_type, operator: @operator, location: @location, amount_in_cents: 4000)
    end
    @door = Door.create!(
      name: "Approval Gate Door", slug: "approval-door-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99088, available: true,
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

  def build_guest(approved:)
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, approved: approved,
                    original_location: @location, current_location: @location)
      create(:day_pass, user: user, billable: user, operator: @operator,
             location: @location, day_pass_type: @type, day: @tuesday)
      user
    end
  end

  test "unapproved user with a valid day pass gets no keys and no unlock" do
    guest = build_guest(approved: false)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      get "/api/v1/doors", headers: headers(guest)
      assert_response :success
      assert_equal [], JSON.parse(response.body)

      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(guest)
      assert_response :forbidden
      assert_match(/pending approval/i, JSON.parse(response.body)["message"])
      assert_not_requested :post, @kisi_url
    end
  end

  test "approved user with the same day pass unlocks" do
    guest = build_guest(approved: true)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(guest)
      assert_response :success
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "unapproved user with an in-window reservation is still denied" do
    guest = ActsAsTenant.with_tenant(@operator) do
      create(:user, operator: @operator, approved: false,
             original_location: @location, current_location: @location)
    end
    travel_to @zone.parse("#{@tuesday} 10:00") do
      room = ActsAsTenant.with_tenant(@operator) do
        create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, rentable: true)
      end
      Reservation.new(user: guest, room: room,
                      datetime_in: 30.minutes.from_now, minutes: 60).save!(validate: false)
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(guest)
      assert_response :forbidden
      assert_not_requested :post, @kisi_url
    end
  end

  test "unapproved user with an active membership is still denied" do
    member = ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, approved: false,
                    original_location: @location, current_location: @location)
      plan = create(:plan, operator: @operator, location: @location, building_access_level: :all_hours)
      create(:subscription, plan: plan, subscribable: user, billable: user, active: true, paused: false)
      user
    end
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(member)
      assert_response :forbidden
    end
  end

  test "staff keep access regardless of the approved flag" do
    admin = users(:cowork_tahoe_admin)
    admin.update!(approved: false)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(admin)
      assert_response :success
    end
  end
end
