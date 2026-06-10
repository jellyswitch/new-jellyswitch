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
end
