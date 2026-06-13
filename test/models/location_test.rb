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
end
