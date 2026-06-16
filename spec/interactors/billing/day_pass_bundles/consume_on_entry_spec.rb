require "rails_helper"

RSpec.describe Billing::DayPassBundles::ConsumeOnEntry do
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, day_pass_period_start: "04:00") }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }

  def active_bundle(remaining: 5)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: type, quantity_purchased: 5, passes_remaining: remaining, purchased_at: Time.current)
  end
  def consume = described_class.call(user: user, location: location)

  it "burns one pass and mints today's DayPass when uncovered with an active bundle" do
    b = active_bundle
    expect { consume }.to change { b.reload.passes_remaining }.from(5).to(4)
                     .and change { DayPass.where(user: user, day: Date.current, location: location).count }.by(1)
    r = b.redemptions.order(:id).last
    expect(r.kind).to eq("entry")
    expect(r.day_pass).to eq(DayPass.where(user: user, location: location).order(:id).last)
  end

  it "is idempotent — a second entry the same calendar day does NOT burn again" do
    b = active_bundle
    consume
    expect { consume }.not_to change { b.reload.passes_remaining }
  end

  it "does NOT burn when the user already has a day pass for today" do
    b = active_bundle
    DayPass.create!(user: user, billable: user, operator: operator, location: location, day_pass_type: type, day: Date.current)
    expect { consume }.not_to change { b.reload.passes_remaining }
  end

  it "does NOT burn when there is no active bundle" do
    active_bundle(remaining: 0)
    expect { consume }.not_to change(DayPass, :count)
  end

  it "does NOT burn when the user has an active subscription" do
    b = active_bundle
    allow_any_instance_of(User).to receive(:has_active_subscription?).and_return(true)
    expect { consume }.not_to change { b.reload.passes_remaining }
  end

  # --- Period idempotency across midnight ---
  # 6pm today and 1am tomorrow are in the SAME 04:00-rollover window.
  # Burning at 6pm must prevent a second burn at 1am.
  it "does NOT burn a second time when re-entering within the same business-day period (crossing midnight)" do
    b = active_bundle
    tz = ActiveSupport::TimeZone[location.time_zone]

    # Consume at 6pm today (well inside the current business-day window)
    travel_to(tz.parse("2026-06-15 18:00")) do
      consume
    end
    expect(b.reload.passes_remaining).to eq(4)

    # Re-enter at 1am the next calendar day — still same business-day window (rollover at 04:00)
    travel_to(tz.parse("2026-06-16 01:00")) do
      expect { consume }.not_to change { b.reload.passes_remaining }
    end
  end

  # --- Inside-lock re-check (concurrency proof) ---
  # Calling consume twice in rapid succession in the same period burns exactly one pass.
  # The redemption-window check inside with_lock guarantees deterministic idempotency.
  it "calling consume twice in the same business-day period burns exactly one pass" do
    b = active_bundle
    consume
    consume
    expect(b.reload.passes_remaining).to eq(4)
    expect(b.redemptions.where(kind: "entry").count).to eq(1)
  end

  it "inside-lock re-check: no burn when an entry redemption for the current window appears right as the lock is acquired" do
    b = active_bundle
    window_start, _window_end = location.business_day_window

    # Simulate a concurrent T1 that committed an entry redemption inside the window
    # AFTER our outer coverage guards ran but BEFORE we acquire the lock.
    # We inject only the redemption row (not the decrement) — T2 (the interactor)
    # should see it and bail without decrementing.
    allow_any_instance_of(DayPassBundle).to receive(:with_lock).and_wrap_original do |orig, *args, &blk|
      b.reload
      b.redemptions.create!(
        operator: operator,
        kind: "entry",
        performed_by: user,
        redeemed_at: window_start + 1.minute
      )
      orig.call(*args, &blk)
    end

    expect { described_class.call(user: user, location: location) }
      .not_to change { b.reload.passes_remaining }
  end
end
