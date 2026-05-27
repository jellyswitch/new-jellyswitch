require "test_helper"

# Coverage for /api/v1/admin/reservations (the all-bookings list the
# mobile admin's Reservations screen calls). Same regression as
# Api::V1::Admin::MembersController#reservations: the JSON didn't
# include `ended_early`, so the screen rendered ended-early bookings
# identically to active ones AND offered Extend/Cancel buttons on
# finished reservations.
class Api::V1::Admin::ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)

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

  test "index payload includes ended_early so the all-bookings list can badge it" do
    # The "room_reservation_today" fixture's <%= Time.zone.today %> lands
    # at the prior PDT day after YAML/timestamptz conversion, so the
    # controller's `today` scope skips it. Pin datetime_in explicitly.
    reservations(:room_reservation_today).update!(
      ended_early: true,
      datetime_in: Time.zone.now.change(hour: 10),
    )

    get "/api/v1/admin/reservations", params: { scope: "today" }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation_today).id }
    refute_nil match, "expected the ended-early reservation in today's scope"
    assert_equal true, match["ended_early"],
      "ended_early must be surfaced or the admin all-bookings list can't distinguish from active rows"
  end

  test "index payload includes ended_early=false for active bookings" do
    reservations(:room_reservation_today).update!(
      ended_early: false,
      datetime_in: Time.zone.now.change(hour: 10),
    )

    get "/api/v1/admin/reservations", params: { scope: "today" }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation_today).id }
    refute_nil match
    assert_equal false, match["ended_early"]
  end
end
