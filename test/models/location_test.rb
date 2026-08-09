require "test_helper"

# Working-hours times are fed verbatim into the `working_hours` gem, which only
# accepts zero-padded 24h "HH:MM". A value like "5:00" (easy to fat-finger into
# the free-text Settings > Hours field) raised WorkingHours::InvalidConfiguration
# and 500'd the whole operator dashboard (Operator::LandingController#home).
# We normalize on assignment so common typos self-heal, and reject genuinely
# malformed values at the source.
class LocationTest < ActiveSupport::TestCase
  test "normalizes a single-digit hour to zero-padded HH:MM on assignment" do
    assert_equal "05:00", Location.new(working_day_start: "5:00").working_day_start
    assert_equal "09:30", Location.new(working_day_start: "9:30").working_day_start
    assert_equal "06:00", Location.new(working_day_end: "6:00").working_day_end
  end

  test "leaves already-padded times untouched" do
    assert_equal "06:00", Location.new(working_day_start: "06:00").working_day_start
    assert_equal "18:00", Location.new(working_day_end: "18:00").working_day_end
  end

  test "normalizes a bare hour to HH:00" do
    assert_equal "05:00", Location.new(working_day_start: "5").working_day_start
  end

  test "drops seconds when normalizing" do
    assert_equal "05:00", Location.new(working_day_start: "5:00:00").working_day_start
  end

  test "blank is left blank for the presence validation to catch" do
    loc = Location.new(working_day_start: "")
    loc.valid?
    assert_includes loc.errors[:working_day_start], "can't be blank"
  end

  test "rejects a malformed time" do
    loc = Location.new(working_day_start: "abc")
    loc.valid?
    assert loc.errors[:working_day_start].any?, "expected a format error for 'abc'"
  end

  test "rejects an out-of-range hour" do
    loc = Location.new(working_day_start: "25:00")
    loc.valid?
    assert loc.errors[:working_day_start].any?, "expected a format error for '25:00'"
  end

  test "a normalized single-digit time passes the format validation" do
    loc = Location.new(working_day_start: "5:00")
    loc.valid?
    assert_empty loc.errors[:working_day_start]
  end

  test "posted_hours_span returns the local open..close instants for a date" do
    loc = locations(:cowork_tahoe_location)
    loc.update!(time_zone: "America/Los_Angeles", working_day_start: "08:00", working_day_end: "18:00")
    span = loc.posted_hours_span(Date.new(2026, 8, 13))
    assert_equal Time.find_zone!("America/Los_Angeles").local(2026, 8, 13, 8, 0), span.first
    assert_equal Time.find_zone!("America/Los_Angeles").local(2026, 8, 13, 18, 0), span.last
  end

  test "posted_hours_span is nil for blank or overnight windows" do
    loc = locations(:cowork_tahoe_location)
    # Attribute assignment only (no save): working_day_start has a presence
    # validation, so update! with a blank value would raise RecordInvalid
    # instead of exercising the nil-return path under test here.
    loc.working_day_start = ""
    loc.working_day_end = "18:00"
    assert_nil loc.posted_hours_span(Date.current)

    loc.working_day_start = "22:00"
    loc.working_day_end = "05:00"
    assert_nil loc.posted_hours_span(Date.current)
  end

  test "posted_hours_span keeps wall-clock times across DST transitions" do
    loc = locations(:cowork_tahoe_location)
    loc.update!(time_zone: "America/Los_Angeles", working_day_start: "08:00", working_day_end: "18:00")
    span = loc.posted_hours_span(Date.new(2026, 3, 8)) # US spring-forward date
    assert_equal 8, span.first.hour
    assert_equal 18, span.last.hour
  end

  test "posted_hours_span is nil for a zero-length window" do
    loc = locations(:cowork_tahoe_location)
    # Attribute assignment only (no save) — see the blank/overnight test above.
    loc.working_day_start = "09:00"
    loc.working_day_end = "09:00"
    assert_nil loc.posted_hours_span(Date.current)
  end

  test "posted_hours_span rolls a working_day_end of 24:00 into the next day" do
    loc = locations(:cowork_tahoe_location)
    # Attribute assignment only (no save), like the blank test.
    loc.time_zone = "America/Los_Angeles"
    loc.working_day_start = "08:00"
    loc.working_day_end = "24:00"
    date = Date.new(2026, 8, 13)
    span = loc.posted_hours_span(date)
    assert_equal Time.find_zone!("America/Los_Angeles").local(2026, 8, 14, 0, 0), span.last
    assert_equal date, span.first.to_date
  end

  test "posted_hours_span reflects real elapsed minutes across a DST spring-forward" do
    loc = locations(:cowork_tahoe_location)
    loc.update!(time_zone: "America/Los_Angeles", working_day_start: "01:00", working_day_end: "04:00")
    span = loc.posted_hours_span(Date.new(2026, 3, 8)) # US spring-forward date: 2am -> 3am doesn't exist
    assert_equal 120, ((span.last - span.first) / 60).round # not the naive 180
  end
end
