require "test_helper"

# The secondary line under each timeline card. Reservations are the interesting
# case: occurred_at is when the member clicked "book", which tells staff nothing
# about when the room was held, so those cards show the booked window instead.
class ActivityTimelineHelperTest < ActionView::TestCase
  include ActivityTimelineHelper

  def activity(kind:, payload: {}, occurred_at: Time.zone.parse("2026-08-14 09:15"), subject_id: nil)
    Activity.new(kind: kind, payload: payload, occurred_at: occurred_at, subject_id: subject_id)
  end

  test "reservation shows the booked window and duration, not the booking time" do
    subtitle = activity_timeline_subtitle(activity(
      kind: "reservation",
      payload: { "datetime_in" => "2026-08-18T14:00:00-07:00", "minutes" => 90 },
      occurred_at: Time.zone.parse("2026-08-01 08:00"),
    ))

    assert_equal "Aug 18, 2026 · 2pm–3:30pm · 1h 30m", subtitle
    assert_not_includes subtitle, "8:00am" # the moment they clicked book
  end

  test "reservation renders the window in the room's zone, not the app zone" do
    # Same instant, written with the room's offset. Rendering it in UTC (Heroku's
    # Time.zone) would show 9pm — the member booked 2pm local.
    subtitle = activity_timeline_subtitle(activity(
      kind: "reservation",
      payload: { "datetime_in" => "2026-08-18T14:00:00-07:00", "minutes" => 60 },
    ))

    assert_includes subtitle, "2pm–3pm"
  end

  test "a cancelled reservation says so rather than reading as a live booking" do
    subtitle = activity_timeline_subtitle(activity(
      kind: "reservation",
      payload: { "datetime_in" => "2026-08-18T14:00:00-07:00", "minutes" => 60, "cancelled" => true },
    ))

    assert_equal "Aug 18, 2026 · 2pm–3pm · 1h · cancelled", subtitle
  end

  test "sub-hour and multi-hour durations both read naturally" do
    assert_equal "45m", pretty_duration(45)
    assert_equal "2h", pretty_duration(120)
    assert_equal "2h 15m", pretty_duration(135)
  end

  # Pre-payload rows (very old activities, backfill misses) must not blow up or
  # render a blank line — they fall back to the booking timestamp.
  test "reservation with no payload falls back to occurred_at" do
    subtitle = activity_timeline_subtitle(activity(kind: "reservation", payload: {}))

    assert_equal "Aug 14, 2026 · 9:15am", subtitle
  end

  test "day pass reports the room time booked on its day" do
    day = Date.new(2026, 8, 14)
    index = Minitest::Mock.new
    index.expect(:minutes_on, 210, [day])

    subtitle = activity_timeline_subtitle(
      activity(kind: "day_pass", payload: { "day" => day.iso8601 }),
      hours: index,
    )

    assert_equal "Aug 14, 2026 · 3h 30m booked", subtitle
    index.verify
  end

  test "day pass with no reservations says so instead of showing 0m" do
    day = Date.new(2026, 8, 14)
    index = Minitest::Mock.new
    index.expect(:minutes_on, 0, [day])

    subtitle = activity_timeline_subtitle(
      activity(kind: "day_pass", payload: { "day" => day.iso8601 }),
      hours: index,
    )

    assert_equal "Aug 14, 2026 · no room time booked", subtitle
  end

  test "bundle reports passes used and hours booked across the pack" do
    index = Minitest::Mock.new
    index.expect(:bundle, { quantity: 10, used: 4, minutes: 330 }, [77])

    subtitle = activity_timeline_subtitle(
      activity(kind: "day_pass_bundle", subject_id: 77, payload: { "quantity" => 10 }),
      hours: index,
    )

    assert_equal "Aug 14, 2026 · 4 of 10 used · 5h 30m booked", subtitle
    index.verify
  end

  test "bundle label names the pack size" do
    assert_equal "Bought a 10-pack day pass bundle",
                 activity_label(activity(kind: "day_pass_bundle", payload: { "quantity" => 10 }))
    assert_equal "Bought a day pass bundle",
                 activity_label(activity(kind: "day_pass_bundle", payload: {}))
  end

  test "kinds without an hours story keep the plain timestamp" do
    assert_equal "Aug 14, 2026 · 9:15am",
                 activity_timeline_subtitle(activity(kind: "checkin", payload: { "location_name" => "Tahoe" }))
  end
end
