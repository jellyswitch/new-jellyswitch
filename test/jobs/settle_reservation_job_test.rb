require "test_helper"

class SettleReservationJobTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
  end

  # A reservation that was moved later leaves a stale SettleReservationJob
  # queued at the OLD (earlier) start. If it fires before the new start it
  # must NOT capture — otherwise an edited booking gets charged early.
  test "does not capture when the reservation start is still in the future" do
    res = Reservation.create!(
      user: @user, room: @room,
      datetime_in: 3.hours.from_now, minutes: 60,
      stripe_payment_intent_id: "pi_test_stale",
    )

    Billing::Reservations::CaptureHold.expects(:call).never

    SettleReservationJob.perform_now(res.id)
  end

  test "captures when the reservation start has arrived" do
    res = Reservation.create!(
      user: @user, room: @room,
      datetime_in: 1.minute.ago, minutes: 60,
      stripe_payment_intent_id: "pi_test_due",
    )

    Billing::Reservations::CaptureHold.expects(:call).once

    SettleReservationJob.perform_now(res.id)
  end
end
