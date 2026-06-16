require "rails_helper"

# End-to-end lifecycle: buy → enter → re-enter (idempotent) → guest → balance check.
# Stripe is stubbed exactly as create_bundle_spec does; every other code path is real.
RSpec.describe "DayPassBundle full member lifecycle", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  # ---------------------------------------------------------------------------
  # SETUP
  # ---------------------------------------------------------------------------
  let(:operator) { create(:operator) }
  let(:location)  { create(:location, operator: operator, day_pass_period_start: "04:00") }

  # out_of_band: true → ChargeBundleInvoice short-circuits (same billing bypass
  # used in create_bundle_spec). We still need a stripe_customer_id so SaveBundle's
  # billing lookup doesn't blow up.
  let(:user) do
    create(:user, operator: operator, out_of_band: true).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_lifecycle_test_123")
    end
  end

  let(:day_pass_type) do
    create(:day_pass_type,
           operator:          operator,
           location:          location,
           quantity:          5,
           amount_in_cents:   10_000)
  end

  # Mirror the Stripe stubs from create_bundle_spec verbatim.
  before do
    fake_stripe_inv = double("stripe_invoice",
      id:          "in_lifecycle_1",
      customer:    "cus_lifecycle_test_123",
      amount_due:  10_000,
      amount_paid: 0,
      number:      "INV-LC001",
      created:     Time.current.to_i,
      due_date:    nil,
      status:      "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_lc1"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_stripe_inv)
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable:          user,
        operator_id:       operator.id,
        amount_due:        10_000,
        amount_paid:       0,
        stripe_invoice_id: "in_lifecycle_1",
        date:              Time.current,
        status:            "draft",
        location_id:       location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end
  end

  it "walks the full lifecycle: buy → enter → re-enter (no burn) → guest → ledger check → access check" do
    # We pin time to a fixed afternoon so every within-period guard behaves predictably.
    # 2026-06-16 14:00 UTC is safely inside the 04:00–04:00+24h business-day window.
    tz = ActiveSupport::TimeZone["UTC"]

    # Declare bundle in the outer scope so it is accessible across all travel_to blocks.
    bundle = nil

    travel_to(tz.parse("2026-06-16 14:00:00")) do

      # -----------------------------------------------------------------------
      # PHASE 1 — Buy the 5-Pack
      # -----------------------------------------------------------------------
      ctx = Billing::DayPassBundles::CreateBundle.call(
        params:      { day_pass_type: day_pass_type.id },
        user_id:     user.id,
        operator:    operator,
        location:    location,
        out_of_band: true
      )

      expect(ctx).to be_success, "Phase 1 FAILED: CreateBundle returned failure — #{ctx.message}"
      bundle = ctx.day_pass_bundle

      # Exactly one bundle created
      expect(DayPassBundle.count).to eq(1),
        "Phase 1: expected 1 DayPassBundle, got #{DayPassBundle.count}"
      expect(bundle.passes_remaining).to eq(5),
        "Phase 1: passes_remaining should be 5, got #{bundle.passes_remaining}"
      expect(bundle.quantity_purchased).to eq(5),
        "Phase 1: quantity_purchased should be 5, got #{bundle.quantity_purchased}"
      # No DayPass rows yet (bundle purchase does NOT mint entry passes)
      expect(DayPass.count).to eq(0),
        "Phase 1: expected 0 DayPass rows, got #{DayPass.count}"

      # -----------------------------------------------------------------------
      # PHASE 2 — Walk in (burn 1 pass)
      # -----------------------------------------------------------------------
      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      bundle.reload

      expect(bundle.passes_remaining).to eq(4),
        "Phase 2: passes_remaining should be 4 after entry, got #{bundle.passes_remaining}"

      # One DayPass for today at this location
      today = Date.current
      entry_pass = DayPass.where(user: user, location: location, day: today)
      expect(entry_pass.count).to eq(1),
        "Phase 2: expected 1 DayPass for today, got #{entry_pass.count}"

      # The redemption is recorded as kind=entry
      last_redemption = bundle.redemptions.order(:id).last
      expect(last_redemption.kind).to eq("entry"),
        "Phase 2: expected last redemption kind='entry', got '#{last_redemption.kind}'"

    end  # end travel_to 14:00

    # -----------------------------------------------------------------------
    # PHASE 3 — Re-enter the SAME business-day period (must NOT burn again).
    # Re-enter 30 minutes later — still inside the same 04:00-rollover window.
    # -----------------------------------------------------------------------
    travel_to(tz.parse("2026-06-16 14:30:00")) do
      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      bundle.reload

      expect(bundle.passes_remaining).to eq(4),
        "Phase 3 (idempotent re-entry): passes_remaining should STILL be 4, got #{bundle.passes_remaining}"
      expect(bundle.redemptions.where(kind: "entry").count).to eq(1),
        "Phase 3: expected exactly 1 entry redemption, got #{bundle.redemptions.where(kind: 'entry').count}"
    end

    # -----------------------------------------------------------------------
    # PHASE 4 — Bring a guest (burn 1 pass)
    # -----------------------------------------------------------------------
    travel_to(tz.parse("2026-06-16 15:00:00")) do
      guest_ctx = Billing::DayPassBundles::CheckInGuest.call(
        bundle:       bundle,
        performed_by: user,
        guest_name:   "Sam"
      )
      expect(guest_ctx).to be_success,
        "Phase 4 FAILED: CheckInGuest returned failure — #{guest_ctx.message}"

      bundle.reload
      expect(bundle.passes_remaining).to eq(3),
        "Phase 4: passes_remaining should be 3 after guest check-in, got #{bundle.passes_remaining}"

      # The guest redemption is recorded with the right attributes
      guest_redemption = bundle.redemptions.where(kind: "guest").last
      expect(guest_redemption).not_to be_nil, "Phase 4: no guest redemption found"
      expect(guest_redemption.guest_name).to eq("Sam"),
        "Phase 4: guest_name should be 'Sam', got '#{guest_redemption.guest_name}'"

      # -----------------------------------------------------------------------
      # PHASE 5 — Ledger integrity: exactly [entry, guest] in order
      # -----------------------------------------------------------------------
      kinds = bundle.redemptions.order(:id).pluck(:kind)
      expect(kinds).to eq(%w[entry guest]),
        "Phase 5: expected redemption kinds [entry, guest], got #{kinds.inspect}"
      expect(bundle.passes_remaining).to eq(3),
        "Phase 5: balance should be 3, got #{bundle.passes_remaining}"

      # -----------------------------------------------------------------------
      # PHASE 6 — Access check: user still has an active bundle at this location
      # -----------------------------------------------------------------------
      expect(user.has_active_day_pass_bundle?(location)).to be(true),
        "Phase 6: has_active_day_pass_bundle? should be true (3 passes remain)"
    end
  end
end
