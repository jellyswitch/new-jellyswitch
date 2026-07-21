require "test_helper"

# The dashboard door buttons must gate on the SAME predicate as the unlock
# endpoint (user_can_access_building?), so buttons render if and only if a
# tap would succeed. The old gate (Permissions#has_building_access?) had no
# reservation clause, so a reservation-only visitor inside their ±window
# (ADR 0013) saw no unlock buttons at all despite a valid unlock right.
class Api::V1::DashboardDoorsTest < ActionDispatch::IntegrationTest
  setup do
    @non_member = users(:cowork_tahoe_non_member)
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @door       = Door.create!(
      name:      "Cowork Tahoe Front",
      slug:      "ct-front-#{SecureRandom.hex(4)}",
      location:  @location,
      operator:  @operator,
      kisi_id:   99010,
      available: true,
    )
  end

  def headers(user)
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

  def reservation_at(datetime_in)
    room = Room.create!(name: "RW-#{SecureRandom.hex(3)}", slug: "rw-#{SecureRandom.hex(4)}",
                        location: @location, operator: @operator, rentable: true)
    Reservation.new(user: @non_member, room: room,
                    datetime_in: datetime_in, minutes: 60).save!(validate: false)
  end

  def dashboard_door_ids
    get "/api/v1/dashboard", headers: headers(@non_member)
    assert_response :success
    JSON.parse(response.body)["doors"].map { |d| d["id"] }
  end

  test "dashboard shows door buttons for a reservation-only visitor inside the access window" do
    reservation_at(30.minutes.from_now)
    assert_includes dashboard_door_ids, @door.id
  end

  test "dashboard hides door buttons for a reservation-only visitor outside the access window" do
    reservation_at(3.days.from_now.change(hour: 12))
    assert_equal [], dashboard_door_ids
  end
end
