require "rails_helper"

RSpec.describe Location, "#business_day_window" do
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:operator) }
  # Use a fixed, well-known tz so wall-clock times are deterministic.
  let(:location) { create(:location, operator: operator, time_zone: "Pacific Time (US & Canada)", day_pass_period_start: "04:00") }

  # Helper: build a Time in the location's zone from a date + hour:min string.
  def pacific(date_str, time_str)
    ActiveSupport::TimeZone["Pacific Time (US & Canada)"].parse("#{date_str} #{time_str}")
  end

  it "6pm Monday and 1am Tuesday are in the SAME window (04:00 rollover)" do
    mon_6pm  = pacific("2026-06-15", "18:00")  # Monday 18:00 PT
    tue_1am  = pacific("2026-06-16", "01:00")  # Tuesday 01:00 PT — same business day

    window_a = location.business_day_window(mon_6pm)
    window_b = location.business_day_window(tue_1am)

    expect(window_a).to eq(window_b)
  end

  it "5am Tuesday is in the NEXT window (after 04:00 rollover)" do
    mon_6pm  = pacific("2026-06-15", "18:00")  # Monday 18:00 PT
    tue_5am  = pacific("2026-06-16", "05:00")  # Tuesday 05:00 PT — next business day

    window_monday = location.business_day_window(mon_6pm)
    window_tuesday = location.business_day_window(tue_5am)

    expect(window_tuesday).not_to eq(window_monday)
    # Tuesday window starts at 04:00 Tuesday
    expected_start = pacific("2026-06-16", "04:00")
    expect(window_tuesday[0]).to eq(expected_start)
    expect(window_tuesday[1]).to eq(expected_start + 1.day)
  end

  it "window start and end are exactly 24 hours apart" do
    at = pacific("2026-06-15", "14:30")
    start, finish = location.business_day_window(at)
    expect(finish - start).to eq(1.day)
  end

  it "an entry at exactly the rollover time (04:00) starts the NEW window" do
    exactly_rollover = pacific("2026-06-16", "04:00")
    window = location.business_day_window(exactly_rollover)
    expect(window[0]).to eq(exactly_rollover)
  end

  it "one second before the rollover (03:59:59) is still in the PREVIOUS window" do
    just_before = pacific("2026-06-16", "03:59") - 1.second
    window = location.business_day_window(just_before)
    # Window should start on Monday 04:00, not Tuesday 04:00
    expect(window[0]).to eq(pacific("2026-06-15", "04:00"))
  end
end
