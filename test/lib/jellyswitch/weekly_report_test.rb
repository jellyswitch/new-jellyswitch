require "test_helper"

module Jellyswitch
  class WeeklyReportTest < ActiveSupport::TestCase
    setup do
      @operator = operators(:cowork_tahoe)
      @location = locations(:cowork_tahoe_location)
      @room     = rooms(:small_meeting_room)
      @user     = users(:cowork_tahoe_member)

      Reservation.where(room: @location.rooms).delete_all

      Time.use_zone(@location.time_zone) do
        @week_start = Time.current.beginning_of_week - 1.week
        @week_end   = Time.current.end_of_week - 1.week
      end
    end

    # 60 business hours per week: 6am-6pm, Monday-Friday.
    AVAILABLE_MINUTES = 5 * 12 * 60

    def report
      Time.use_zone(@location.time_zone) do
        Jellyswitch::WeeklyReport.new(@operator, @location, @week_start, @week_end)
      end
    end

    def room_entry(rep, room)
      rep.rooms.find { |r| r[:name] == room.name }
    end

    def zone
      ActiveSupport::TimeZone[@location.time_zone]
    end

    # day_offset 0 = the SUNDAY of the reported week (the app's weeks run
    # Sunday-Saturday), so 1 = Monday ... 6 = Saturday.
    def book(day_offset:, hour:, minutes:, room: @room, cancelled: false)
      day = @week_start.to_date + day_offset
      Reservation.create!(
        user: @user,
        room: room,
        datetime_in: zone.local(day.year, day.month, day.day, hour),
        minutes: minutes,
        cancelled: cancelled,
      )
    end

    test "archived rooms are left out of the per-room usage list" do
      archived = Room.create!(
        name: "Retired Phone Booth", operator: @operator, location: @location,
        archived: true,
      )

      names = report.rooms.map { |r| r[:name] }
      refute_includes names, archived.name
      assert_includes names, @room.name
    end

    test "an in-window booking counts its full duration against 60 business hours" do
      book(day_offset: 2, hour: 9, minutes: 120) # Tuesday 9-11am

      assert_in_delta 120.0 / AVAILABLE_MINUTES, room_entry(report, @room)[:utilization], 0.001
    end

    test "booked time outside 6am-6pm is clipped" do
      book(day_offset: 1, hour: 17, minutes: 180) # Monday 5-8pm → only 5-6pm counts

      assert_in_delta 60.0 / AVAILABLE_MINUTES, room_entry(report, @room)[:utilization], 0.001
    end

    test "weekend bookings contribute nothing" do
      book(day_offset: 6, hour: 10, minutes: 120) # Saturday

      entry = room_entry(report, @room)
      assert_in_delta 0.0, entry[:utilization], 0.0001
      # The reservation still happened, so it stays in the count.
      assert_equal 1, entry[:count]
    end

    test "cancelled reservations count for nothing" do
      book(day_offset: 2, hour: 9, minutes: 60, cancelled: true)

      entry = room_entry(report, @room)
      assert_in_delta 0.0, entry[:utilization], 0.0001
      assert_equal 0, entry[:count]
    end

    test "rooms are ordered busiest first" do
      other = rooms(:large_meeting_room)
      book(day_offset: 2, hour: 9, minutes: 60)
      book(day_offset: 2, hour: 9, minutes: 240, room: other)

      names = report.rooms.map { |r| r[:name] }
      assert names.index(other.name) < names.index(@room.name)
    end
  end
end
