require "test_helper"
require "stripe_mock"

class ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)

    @reservation = reservations(:future_room_reservation)
  end

  test "should cancel reservation successfully" do
    log_in @admin
    CancelReservation.stubs(:call).returns(OpenStruct.new(success?: true))

    delete reservation_path(@reservation), env: default_env

    assert :success
    assert_redirected_to root_path
    assert_equal "Reservation cancelled.", flash[:notice]
  end

  test "should return error message when cancel reservation failed" do
    log_in @admin

    expected_message = "Unable to cancel reservation."
    CancelReservation.stubs(:call).returns(OpenStruct.new(success?: false, message: expected_message))

    delete reservation_path(@reservation), env: default_env

    assert_equal expected_message, flash[:error]
  end

  # --- reassign_room (Task 12, ADR 0026) ------------------------------------

  # Builds a live Day Office hold under @operator/@location and returns
  # [hold, room_a, room_b] — Allocator fills position order, so the hold
  # always lands on room_a first (mirrors DayOffices::ReassignRoomTest).
  def make_office_hold(user: @member, day: 3.days.from_now.to_date)
    hold = nil
    room_a = room_b = nil
    ActsAsTenant.with_tenant(@operator) do
      _bundle, room_a, room_b = make_office_bundle(member: user)
      pass = DayPass.create!(user: user, billable: user, operator: @operator, location: @location,
                             day_pass_type: _bundle.day_pass_type, day: day, imported: true)
      hold = DayOffices::Allocator.allocate!(day_pass: pass)
    end
    [hold, room_a, room_b]
  end

  test "staff can reassign a Day Office hold to a free room" do
    hold, room_a, room_b = make_office_hold
    log_in @admin

    patch reassign_room_reservation_path(hold), params: { room_id: room_b.id }, env: default_env

    assert_redirected_to root_path
    assert_equal "Office hold moved to #{room_b.name}.", flash[:notice]
    assert_equal room_b, hold.reload.room
  end

  test "flashes an error and redirects back when the target room is full" do
    hold, room_a, room_b = make_office_hold
    Reservation.create!(user: users(:cowork_tahoe_non_member), room: room_b,
                        datetime_in: hold.datetime_in, minutes: hold.minutes)
    log_in @admin

    patch reassign_room_reservation_path(hold), params: { room_id: room_b.id }, env: default_env

    assert_redirected_to root_path
    assert_match(/already booked/i, flash[:error])
    assert_equal room_a, hold.reload.room
  end

  test "flashes 'Already in' for a same-room reassignment, and does not claim a move" do
    hold, room_a, room_b = make_office_hold
    log_in @admin

    patch reassign_room_reservation_path(hold), params: { room_id: room_a.id }, env: default_env

    assert_redirected_to root_path
    assert_equal "Already in #{room_a.name}.", flash[:notice]
    assert_equal room_a, hold.reload.room
  end

  test "flashes an error for a cancelled (released) hold instead of a raw 404" do
    hold, room_a, room_b = make_office_hold
    hold.update_columns(cancelled: true)
    log_in @admin

    patch reassign_room_reservation_path(hold), params: { room_id: room_b.id }, env: default_env

    assert_redirected_to root_path
    assert_match(/no longer active/i, flash[:error])
  end

  test "a non-staff member is refused — house Pundit denial, not a crash" do
    hold, room_a, room_b = make_office_hold
    log_in @member

    patch reassign_room_reservation_path(hold), params: { room_id: room_b.id }, env: default_env

    assert_redirected_to root_path # user_not_authorized -> referrer_or_root, no referrer in test -> root
    assert_match(/whoops/i, flash[:alert])
    assert_equal room_a, hold.reload.room, "a denied request must never move the hold"
  end
end
