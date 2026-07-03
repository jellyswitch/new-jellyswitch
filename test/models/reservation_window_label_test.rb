require "test_helper"

class ReservationWindowLabelTest < ActiveSupport::TestCase
  setup do
    @room = rooms(:small_meeting_room) # cowork_tahoe_location, Pacific
    @user = users(:cowork_tahoe_member)
  end

  def build_reservation(hour:, minutes:)
    zone = ActiveSupport::TimeZone[@room.location.time_zone]
    day = Date.current + 7
    Reservation.new(user: @user, room: @room,
      datetime_in: zone.local(day.year, day.month, day.day, hour), minutes: minutes)
  end

  test "same-meridiem window drops the duplicate AM/PM" do
    assert_equal "10:00–11:00 AM", build_reservation(hour: 10, minutes: 60).window_label
  end

  test "cross-meridiem window keeps both" do
    assert_equal "11:30 AM–1:00 PM", build_reservation(hour: 11, minutes: 90)
      .tap { |r| r.datetime_in = r.datetime_in.change(min: 30) }.window_label
  end
end
