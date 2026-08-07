require "test_helper"

# Server-side posted-hours enforcement on the member reservation endpoints
# (Nash incident, 2026-08-07). The pickers already bound what they OFFER
# non-members; these tests pin the backstop for what the API will ACCEPT —
# create, update (move), and extend must all keep a day-pass guest's booking
# inside the location's posted hours, while members book 24/7.
class Api::V1::ReservationsHoursTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false,
                        credits_enabled: false)
      @room = create(:room, operator: @operator, location: @location,
                     hourly_rate_in_cents: 0, include_with_day_pass: true)
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     amount_in_cents: 4000, available: true, visible: true)
      @tuesday  = Date.current.next_occurring(:tuesday) + 7
      @saturday = Date.current.next_occurring(:saturday) + 7
      # Coverage for every date these tests book, so ADR 0019 coverage
      # enforcement never masks the hours check under test.
      [@tuesday, @saturday].each do |day|
        create(:day_pass, user: @guest, billable: @guest, operator: @operator,
               location: @location, day_pass_type: @type, day: day)
      end
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def at(date, hhmm)
    @zone.parse("#{date} #{hhmm}")
  end

  def create_booking(user, datetime_in, minutes: 60)
    post "/api/v1/reservations",
         params: { reservation: { room_id: @room.id, datetime_in: datetime_in.iso8601, minutes: minutes } }.to_json,
         headers: headers(user)
  end

  test "guest with a day pass books inside posted hours" do
    create_booking(@guest, at(@tuesday, "10:00"))
    assert_response :created
  end

  test "guest booking at 2 AM is rejected" do
    assert_no_difference -> { Reservation.where(user_id: @guest.id).count } do
      create_booking(@guest, at(@tuesday, "02:00"))
    end
    assert_response :unprocessable_entity
    assert_match(/open/i, JSON.parse(response.body)["error"].to_s)
  end

  test "guest books Saturday daytime (staffed-day flags don't bound bookings)" do
    create_booking(@guest, at(@saturday, "10:00"))
    assert_response :created
  end

  test "guest booking Saturday at 2 AM is still rejected" do
    create_booking(@guest, at(@saturday, "02:00"))
    assert_response :unprocessable_entity
  end

  test "guest booking that runs past close is rejected" do
    create_booking(@guest, at(@tuesday, "19:30"), minutes: 60)
    assert_response :unprocessable_entity
  end

  test "subscribed member books after close" do
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id)
    create_booking(users(:cowork_tahoe_member), at(@tuesday, "21:00"))
    assert_response :created
  end

  test "guest cannot move a booking outside posted hours" do
    res = ActsAsTenant.with_tenant(@operator) do
      create(:reservation, user: @guest, room: @room, datetime_in: at(@tuesday, "10:00"), minutes: 60)
    end

    patch "/api/v1/reservations/#{res.id}",
          params: { reservation: { datetime_in: at(@tuesday, "02:00").iso8601 } }.to_json,
          headers: headers(@guest)
    assert_response :unprocessable_entity
    assert_equal at(@tuesday, "10:00"), res.reload.datetime_in

    patch "/api/v1/reservations/#{res.id}",
          params: { reservation: { datetime_in: at(@tuesday, "11:00").iso8601 } }.to_json,
          headers: headers(@guest)
    assert_response :success
  end

  test "guest cannot extend a booking past close" do
    res = ActsAsTenant.with_tenant(@operator) do
      create(:reservation, user: @guest, room: @room, datetime_in: at(@tuesday, "19:00"), minutes: 45)
    end

    patch "/api/v1/reservations/#{res.id}/extend_time",
          params: { additional_minutes: 60 }.to_json, headers: headers(@guest)
    assert_response :unprocessable_entity
    assert_equal 45, res.reload.minutes

    patch "/api/v1/reservations/#{res.id}/extend_time",
          params: { additional_minutes: 15 }.to_json, headers: headers(@guest)
    assert_response :success
    assert_equal 60, res.reload.minutes
  end
end
