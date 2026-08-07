require "test_helper"

# ADR 0025: a bundle's included_meeting_room_minutes is the allowance PER
# REDEEMED DAY (operator-set on the bundle type), not a pool across the pack.
# The charge math (User#day_pass_reservation_charge_info) has always scoped
# usage to one day; these tests lock the pairing so a bundle holder gets the
# daily allowance each redeemed day and pays overage beyond it — the Alma
# Quiroga gap (2026-08-06: 328 room-minutes in one day, zero overage, because
# the 2-pack type carried the whole 360-minute pool as if it were daily).
class DayPassBundleDailyAllowanceTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(overage_rate_in_cents: 1500, credits_enabled: false)
      @room = create(:room, operator: @operator, location: @location,
                     hourly_rate_in_cents: 0, include_with_day_pass: true)
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      # Per-day allowance: 180 minutes — the post-ADR-0025 shape of a 2-pack.
      @bundle_type = create(:day_pass_type, operator: @operator, location: @location,
                            quantity: 2, amount_in_cents: 7000, included_meeting_room_minutes: 180)
      @day_one = Date.current.next_occurring(:tuesday) + 7
      @day_two = @day_one + 1
      [@day_one, @day_two].each do |day|
        create(:day_pass, user: @guest, billable: @guest, operator: @operator,
               location: @location, day_pass_type: @bundle_type, day: day)
      end
    end
  end

  def book(day, start_hour, minutes)
    ActsAsTenant.with_tenant(@operator) do
      create(:reservation, user: @guest, room: @room,
             datetime_in: day.in_time_zone.change(hour: start_hour), minutes: minutes)
    end
  end

  test "a booking that crosses the daily allowance pays the crossing portion" do
    book(@day_one, 9, 120)
    info = @guest.day_pass_reservation_charge_info(@location, @day_one, 120)
    assert_equal :partial_overage, info[:charge_type]
    # 120 already used, 60 free left — 60 of the requested 120 are overage.
    assert_equal 60, info[:overage_minutes_rounded]
    assert_equal 1500, info[:overage_amount_in_cents]
  end

  test "once the daily allowance is exhausted a booking is all overage" do
    # Alma's 8/6 shape: 238 minutes already booked against a 180/day allowance —
    # the next 90-minute booking is billed in full at the location rate.
    book(@day_one, 9, 238)
    info = @guest.day_pass_reservation_charge_info(@location, @day_one, 90)
    assert_equal :partial_overage, info[:charge_type]
    assert_equal 90, info[:overage_minutes_rounded]
    assert_equal 2250, info[:overage_amount_in_cents]
  end

  test "the next redeemed day starts a fresh daily allowance" do
    book(@day_one, 9, 238)
    info = @guest.day_pass_reservation_charge_info(@location, @day_two, 90)
    assert_equal :free, info[:charge_type]
    assert_equal 180, info[:remaining_free]
  end

  test "usage within the daily allowance stays free" do
    info = @guest.day_pass_reservation_charge_info(@location, @day_one, 90)
    assert_equal :free, info[:charge_type]
  end
end
