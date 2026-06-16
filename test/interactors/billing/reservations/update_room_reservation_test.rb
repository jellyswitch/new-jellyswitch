require "test_helper"

class Billing::Reservations::UpdateRoomReservationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @room = rooms(:small_meeting_room) # free room — no Stripe involved
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
    @location = @room.location
    @reservation = Reservation.create!(
      user: @user, room: @room,
      datetime_in: 2.days.from_now.change(hour: 10, min: 0), minutes: 60,
    )
  end

  def update!(datetime_in:, minutes:)
    Billing::Reservations::UpdateRoomReservation.call(
      reservation: @reservation,
      new_datetime_in: datetime_in,
      new_minutes: minutes,
      user: @user,
      location: @location,
    )
  end

  test "persists the new start time and duration" do
    new_start = 3.days.from_now.change(hour: 15, min: 0)
    result = update!(datetime_in: new_start, minutes: 90)

    assert result.success?
    @reservation.reload
    assert_equal 90, @reservation.minutes
    assert_equal new_start.to_i, @reservation.start_at.to_i
  end

  test "fails and leaves the record untouched when the new window overlaps another booking" do
    blocker = Reservation.create!(user: @user, room: @room, datetime_in: 4.days.from_now.change(hour: 13), minutes: 60)

    result = update!(datetime_in: blocker.datetime_in, minutes: 60)

    refute result.success?
    assert_match(/conflict/i, result.error.to_s)
    @reservation.reload
    assert_equal 60, @reservation.minutes
    assert_equal 2.days.from_now.change(hour: 10).to_i, @reservation.start_at.to_i
  end

  test "reschedules the upcoming reminder for the new start" do
    new_start = 3.days.from_now.change(hour: 15, min: 0)

    assert_enqueued_with(job: SendReservationReminderJob) do
      update!(datetime_in: new_start, minutes: 60)
    end
  end
end
