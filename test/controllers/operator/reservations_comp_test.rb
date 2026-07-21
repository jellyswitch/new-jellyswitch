require "test_helper"

# Web twin of the mobile admin comp flow: the instant-book confirm page offers
# staff a "Comp — book free of charge" button when booking for another member.
# comp must be staff-only — a member forging the param books a NORMAL charged
# reservation for themselves.
class Operator::ReservationsCompTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @admin  = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @room   = rooms(:small_meeting_room)
    @room.update!(hourly_rate_in_cents: 5000)
    @operator = operators(:cowork_tahoe)
    @operator.update!(billing_state: "production")
    @slot = (Time.current + 10.days).change(hour: 10)
  end

  def booking_params(extra = {})
    {
      room_id: @room.id,
      day: @slot.to_date.to_s,
      hour: @slot.strftime("%l:%M%P").strip,
      duration: 60,
      user_id: @member.id,
    }.merge(extra)
  end

  test "staff comp books a priced room for a member without charging" do
    log_in @admin

    assert_difference -> { Reservation.count }, 1 do
      assert_no_difference -> { Invoice.count } do
        post create_reservation_reservations_path(booking_params(comp: 1)), env: default_env
      end
    end

    reservation = Reservation.order(:created_at).last
    assert_equal @member.id, reservation.user_id
    assert_nil reservation.captured_at, "a comped booking must not capture a charge"
    assert_match(/comped/, flash[:notice])
  end

  test "confirm page offers the comp button to staff booking for a member" do
    log_in @admin

    get confirm_reservations_path(booking_params), env: default_env

    assert_response :success
    assert_match "Comp — book free of charge", response.body
  end

  test "a member cannot comp their own booking with a forged param" do
    log_in @member

    stubbed = Interactor::Context.build(reservation: reservations(:future_room_reservation))
    Billing::Reservations::CreateRoomReservation.expects(:call)
      .with(has_entry(comp: false))
      .returns(stubbed)

    post create_reservation_reservations_path(booking_params(comp: 1)), env: default_env
  end

  test "confirm page hides the comp button from members" do
    log_in @member
    @room.update!(hourly_rate_in_cents: 0)

    get confirm_reservations_path(booking_params.except(:user_id)), env: default_env

    assert_response :success
    assert_no_match(/Comp — book free of charge/, response.body)
  end
end
