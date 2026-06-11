require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  # Gap B: a non-Stripe (comp/manual) subscription has no Stripe billing cycle,
  # so current_billing_period must return the CURRENT one-month anniversary
  # window (derived from the start_date day-of-month), not [start_date, now].
  # The old [start_date, Time.current] window grew from signup forever, so a
  # comped member's "monthly" meeting-room allowance never reset.
  test "current_billing_period returns a resetting monthly window for non-Stripe subs (Gap B)" do
    sub = subscriptions(:cowork_tahoe_subscription)
    # YAML loads `stripe_subscription_id: nil` as the STRING "nil", so force a
    # genuine NULL (as real comp/manual subs have) to take the non-Stripe path.
    sub.update!(stripe_subscription_id: nil, start_date: 70.days.ago) # ~2mo + 10d ago
    assert_not sub.has_stripe_subscription?, "must be a non-Stripe subscription"
    period_start, period_end = sub.current_billing_period

    window_days = (period_end - period_start) / 1.day
    assert_in_delta 30, window_days, 2,
      "window should be ~1 month, not the 70-day span since signup"
    assert period_start > 40.days.ago,
      "period must be the CURRENT anniversary window, not the original start_date"
    assert period_end > Time.current,
      "the current window should still be open"
  end

  # ---- Day Pool: per-plan monthly day limit (has_day_limit / day_limit) ----
  # A day is used when the member opens the door (a door punch) at the plan's
  # location, counted within the current billing period, net of comp days.
  # Reservations/check-ins do NOT burn a day; the gate is decoupled from
  # membership identity (see permissions_test / user_test for that half).

  def day_limited_sub(limit: 10, start_date: 5.days.ago)
    sub = subscriptions(:cowork_tahoe_subscription)
    sub.update!(stripe_subscription_id: nil, start_date: start_date) # non-Stripe → anniversary window
    sub.plan.update!(has_day_limit: true, day_limit: limit, location_id: locations(:cowork_tahoe_location).id)
    sub
  end

  def door_at(location)
    Door.create!(name: "Door #{SecureRandom.hex(3)}", slug: "door-#{SecureRandom.hex(4)}",
                 operator: operators(:cowork_tahoe), location: location)
  end

  def punch!(user, door, at)
    p = DoorPunch.create!(user: user, door: door, operator: operators(:cowork_tahoe))
    p.update_column(:created_at, at)
    p
  end

  test "day_pool_used counts DISTINCT door-punch days at the plan's location in the period" do
    sub = day_limited_sub(limit: 10)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    punch!(member, door, 1.day.ago.change(hour: 9))
    punch!(member, door, 1.day.ago.change(hour: 16)) # same day → still one
    punch!(member, door, 2.days.ago.change(hour: 10))
    punch!(member, door, 3.days.ago.change(hour: 10))

    assert_equal 3, sub.day_pool_used
    assert_equal 7, sub.day_pool_remaining
  end

  # Regression: Groupdate's group_by_day(...).count FILLS the date range with
  # zero-count entries for gap days, so .keys over-counts when punch days aren't
  # consecutive. Only days that actually have a punch may count.
  test "day_pool_used counts only days WITH a punch, not the gaps between them" do
    sub = day_limited_sub(limit: 10)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    punch!(member, door, 1.day.ago.change(hour: 9))
    punch!(member, door, 5.days.ago.change(hour: 9)) # gap: days 2,3,4 have no punch

    assert_equal 2, sub.day_pool_used, "only the 2 punched days count, not the empty gap days"
  end

  test "day_pool_used ignores door punches at OTHER locations" do
    sub = day_limited_sub(limit: 10)
    member = sub.subscribable
    here  = door_at(locations(:cowork_tahoe_location))
    other_loc = Location.create!(name: "Sibling #{SecureRandom.hex(2)}", operator: operators(:cowork_tahoe),
                                 visible: true, time_zone: "Pacific Time (US & Canada)",
                                 working_day_start: "09:00", working_day_end: "18:00")
    there = door_at(other_loc)
    punch!(member, here,  1.day.ago.change(hour: 9))
    punch!(member, there, 2.days.ago.change(hour: 9))

    assert_equal 1, sub.day_pool_used, "only the entry at the plan's location counts"
  end

  test "day_pool_used ignores door punches OUTSIDE the current billing period" do
    sub = day_limited_sub(limit: 10, start_date: 5.days.ago)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    punch!(member, door, 2.days.ago.change(hour: 9))   # inside the window
    punch!(member, door, 10.days.ago.change(hour: 9))  # before window start

    assert_equal 1, sub.day_pool_used
  end

  test "comp days reduce day_pool_used within the period" do
    sub = day_limited_sub(limit: 10)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    punch!(member, door, 1.day.ago.change(hour: 9))
    punch!(member, door, 2.days.ago.change(hour: 9))
    punch!(member, door, 3.days.ago.change(hour: 9))
    CompDay.create!(user: member, operator: operators(:cowork_tahoe),
                    location: locations(:cowork_tahoe_location), occurred_on: 2.days.ago.to_date)

    assert_equal 2, sub.day_pool_used, "3 door-punch days minus 1 comp = 2"
    assert_equal 8, sub.day_pool_remaining
  end

  test "has_days_left? is false once distinct door days reach the limit" do
    sub = day_limited_sub(limit: 3)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    [1, 2, 3].each { |d| punch!(member, door, d.days.ago.change(hour: 9)) }

    refute sub.has_days_left?, "3 of 3 days used on past days → a new day is blocked"
  end

  test "has_days_left? is true while under the limit" do
    sub = day_limited_sub(limit: 3)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    [1, 2].each { |d| punch!(member, door, d.days.ago.change(hour: 9)) }

    assert sub.has_days_left?, "2 of 3 used → a new day is allowed"
  end

  test "has_days_left? allows same-day re-entry even at the limit" do
    sub = day_limited_sub(limit: 3)
    member = sub.subscribable
    door = door_at(locations(:cowork_tahoe_location))
    punch!(member, door, 2.days.ago.change(hour: 9))
    punch!(member, door, 1.day.ago.change(hour: 9))
    punch!(member, door, Time.current.change(hour: 8)) # today is the 3rd day, already used

    assert sub.has_days_left?, "today is already a used day → re-entry is free"
  end

  test "has_days_left? is always true when the plan has no day limit" do
    sub = subscriptions(:cowork_tahoe_subscription)
    sub.plan.update!(has_day_limit: false, day_limit: 0)
    assert sub.has_days_left?
  end

  test "has_days_left? is always true for an organization subscription (no door punches as an entity)" do
    sub = day_limited_sub(limit: 1) # valid, day-limited plan
    org = organizations(:sierra_nevada_organization)
    sub.update!(subscribable: org, subscribable_type: "Organization",
                billable: org, billable_type: "Organization")
    assert sub.has_days_left?, "day limits apply to individual (User) subscriptions only"
  end
end
