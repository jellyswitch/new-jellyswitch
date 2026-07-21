require "test_helper"

# Staff comp bookings: the admin create_reservation endpoint passes comp: true
# and every money-moving step must stand down — no charge captured, no credits
# burned, no "paid room" revenue notification. The member still gets the
# reservation itself (emails, door access) exactly like a paid booking.
class Billing::Reservations::CompBookingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)
    @room.update!(hourly_rate_in_cents: 5000)
    @reservation = Reservation.create!(
      room: @room, user: @user, datetime_in: Time.current + 10.days, minutes: 60,
    )
  end

  test "ChargeAtBooking never prices a comped booking" do
    @room.location.operator.update!(billing_state: "production")
    Billing::Reservations::ChargeCalculator.stubs(:call).raises("must not price a comped booking")

    result = Billing::Reservations::ChargeAtBooking.call(reservation: @reservation, comp: true)

    assert result.success?
    assert_nil @reservation.reload.captured_at
  end

  test "ChargeCredits does not burn credits on a comped booking" do
    @room.location.update!(credits_enabled: true)

    result = Billing::Reservations::ChargeCredits.call(
      reservation: @reservation, user: @user, comp: true,
    )

    assert result.success?, "comp must bypass the credit balance check"
  end

  test "ChargeCredits still enforces balance without comp" do
    @room.location.update!(credits_enabled: true)

    result = Billing::Reservations::ChargeCredits.call(
      reservation: @reservation, user: @user,
    )

    refute result.success?
    assert_match(/Insufficient credit/, result.message)
  end

  test "no paid-room revenue notification for a comped booking" do
    assert_no_enqueued_jobs(only: SendNotificationsJob) do
      SendAdminNotificationForPaidRoom.call(reservation: @reservation, comp: true)
    end
  end

  test "paid-room notification still fires without comp" do
    assert_enqueued_with(job: SendNotificationsJob) do
      SendAdminNotificationForPaidRoom.call(reservation: @reservation)
    end
  end
end
