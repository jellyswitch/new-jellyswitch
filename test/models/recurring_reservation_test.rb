require "test_helper"

class RecurringReservationTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room)
  end

  def build(attrs = {})
    RecurringReservation.new({
      title:             "Test series",
      user:              @user,
      room:              @room,
      operator:          @operator,
      location:          @location,
      duration_minutes:  60,
      time_of_day:       Time.zone.parse("10:00"),
      start_date:        Date.new(2026, 1, 5),  # a Monday
      end_date:          Date.new(2026, 1, 18), # a Sunday, 13 days later
    }.merge(attrs))
  end

  # --- pattern allow-list -----------------------------------------------------

  test "daily is a valid recurrence_pattern" do
    rec = build(recurrence_pattern: "daily")
    assert rec.valid?, rec.errors.full_messages.inspect
  end

  test "bimonthly is a valid recurrence_pattern" do
    rec = build(recurrence_pattern: "bimonthly", day_of_month: 5)
    assert rec.valid?, rec.errors.full_messages.inspect
  end

  test "an unknown pattern is rejected" do
    rec = build(recurrence_pattern: "fortnightly")
    refute rec.valid?
    assert_includes rec.errors[:recurrence_pattern], "is not included in the list"
  end

  # --- occurrence_dates -------------------------------------------------------

  test "daily generates one occurrence per calendar day, weekends included" do
    rec = build(recurrence_pattern: "daily")
    dates = rec.occurrence_dates
    # Jan 5 (Mon) through Jan 18 (Sun) inclusive = 14 days
    assert_equal 14, dates.length
    assert_equal Date.new(2026, 1, 5),  dates.first
    assert_equal Date.new(2026, 1, 18), dates.last
    # Saturday + Sunday must be included (this is the new behavior;
    # daily_weekdays excludes them).
    assert_includes dates, Date.new(2026, 1, 10) # Saturday
    assert_includes dates, Date.new(2026, 1, 11) # Sunday
  end

  test "daily_weekdays still excludes weekends" do
    rec = build(recurrence_pattern: "daily_weekdays")
    dates = rec.occurrence_dates
    refute_includes dates, Date.new(2026, 1, 10) # Saturday
    refute_includes dates, Date.new(2026, 1, 11) # Sunday
    assert_equal 10, dates.length # Mon–Fri x2 weeks
  end

  test "bimonthly anchors to the start month and skips every other" do
    # Jan 5 → six months window. Bimonthly on the 5th should fire
    # Jan, Mar, May (not Feb, Apr, Jun).
    rec = build(
      recurrence_pattern: "bimonthly",
      start_date: Date.new(2026, 1, 5),
      end_date:   Date.new(2026, 6, 30),
      day_of_month: 5,
    )
    dates = rec.occurrence_dates
    assert_equal [Date.new(2026, 1, 5), Date.new(2026, 3, 5), Date.new(2026, 5, 5)], dates
  end

  test "bimonthly works when day_of_month is omitted (falls back to start_date.day)" do
    rec = build(
      recurrence_pattern: "bimonthly",
      start_date: Date.new(2026, 2, 14),
      end_date:   Date.new(2026, 8, 31),
    )
    dates = rec.occurrence_dates
    assert_equal [Date.new(2026, 2, 14), Date.new(2026, 4, 14), Date.new(2026, 6, 14), Date.new(2026, 8, 14)], dates
  end

  # --- pattern_description ----------------------------------------------------

  test "pattern_description handles daily" do
    rec = build(recurrence_pattern: "daily")
    assert_equal "Every day", rec.pattern_description
  end

  test "pattern_description handles bimonthly" do
    rec = build(recurrence_pattern: "bimonthly", day_of_month: 14)
    assert_equal "Every other month on the 14th", rec.pattern_description
  end
end
