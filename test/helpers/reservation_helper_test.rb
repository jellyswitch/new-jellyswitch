require "test_helper"

class ReservationHelperTest < ActionView::TestCase
  include ReservationHelper

  def setup
    @start_hour_time = 6
    @end_hour_time = 20

    @now = Time.zone.parse("2024-06-15 10:00:00")
    Timecop.freeze(@now)
  end

  def teardown
    Timecop.return
  end

  test "should returns array of available timeslot within 15-minute intervals" do
    time_slots = calculate_available_time_slots(Time.zone.today)

    expected_start_time = Time.zone.parse("2024-06-15 10:15:00")
    assert_equal time_slots.first, expected_start_time

    time_slots.each_cons(2) do |current_slot, next_slot|
      assert_equal current_slot + 15.minutes, next_slot, "Time slots should be in 15-minute intervals"
    end

    expected_end_time = Time.zone.parse("2024-06-15 #{@end_hour_time}:00:00")
    assert_equal time_slots.last, expected_end_time
  end
end
