require "rails_helper"

# A refunded day pass used to keep granting access AND block bundle redemption,
# because access + every bundle-redeem dedupe guard key on the mere existence of
# a day_passes row for a day (there is no refunded/void status column). This
# service removes the row(s) tied to a refunded invoice so the pass is truly
# rescinded. Financial history stays on the Invoice + refunds row + feed item.
RSpec.describe Billing::DayPasses::RescindForInvoice do
  let(:operator)      { create(:operator) }
  let(:location)      { create(:location, operator: operator) }
  let(:user)          { create(:user, operator: operator) }
  let(:day_pass_type) { create(:day_pass_type, operator: operator, location: location) }
  let(:invoice)       { create(:invoice, operator: operator, location: location, billable: user) }

  def make_pass(day:, on_invoice: invoice, reservation: nil)
    create(:day_pass,
           user: user, billable: user, operator: operator, location: location,
           day_pass_type: day_pass_type, day: day, invoice: on_invoice, reservation: reservation)
  end

  it "destroys a today-or-future pass tied to the refunded invoice" do
    pass = make_pass(day: Date.current)
    expect { described_class.call(invoice: invoice) }
      .to change { DayPass.exists?(pass.id) }.from(true).to(false)
  end

  it "leaves a genuinely-past pass as usage history" do
    past = make_pass(day: Date.current - 3)
    described_class.call(invoice: invoice)
    expect(DayPass.exists?(past.id)).to be(true)
  end

  it "does not touch passes tied to a different invoice" do
    other_invoice = create(:invoice, operator: operator, location: location, billable: user)
    other = make_pass(day: Date.current, on_invoice: other_invoice)
    described_class.call(invoice: invoice)
    expect(DayPass.exists?(other.id)).to be(true)
  end

  it "leaves a pass that still backs an ACTIVE reservation (option A)" do
    room = create(:room, operator: operator, location: location)
    reservation = create(:reservation, user: user, room: room) # cancelled: false
    pass = make_pass(day: Date.current, reservation: reservation)
    described_class.call(invoice: invoice)
    expect(DayPass.exists?(pass.id)).to be(true)
  end

  it "rescinds a pass whose reservation has been cancelled" do
    room = create(:room, operator: operator, location: location)
    # Attach while active (Reservation's default_scope hides cancelled rows, which
    # would fail the tenant association check at create time), then cancel it.
    reservation = create(:reservation, user: user, room: room)
    pass = make_pass(day: Date.current, reservation: reservation)
    reservation.update_column(:cancelled, true)
    described_class.call(invoice: invoice)
    expect(DayPass.exists?(pass.id)).to be(false)
  end

  it "is a no-op (does not raise) for an invoice with no day passes" do
    expect { described_class.call(invoice: invoice) }.not_to raise_error
  end

  # A refunded PACK (DayPassBundle) used to stay fully spendable: the pack mints
  # no DayPass at purchase, so the day-pass sweep matched nothing (the Kost/TLH
  # case). The pack links to its purchase invoice via DayPassBundle#invoice_id,
  # and zeroing passes_remaining is the revoke — `.active` (passes_remaining > 0)
  # is the sole redemption/access gate.
  describe "pack (bundle) refunds" do
    let(:pack_type) { create(:day_pass_type, operator: operator, location: location, quantity: 2) }

    def make_bundle(on_invoice: invoice, remaining: 2)
      create(:day_pass_bundle,
             user: user, operator: operator, location: location,
             day_pass_type: pack_type, quantity_purchased: 2,
             passes_remaining: remaining, invoice: on_invoice)
    end

    it "zeroes the pack tied to the refunded invoice, one admin_burn ledger row per unused pass" do
      bundle = make_bundle
      expect { described_class.call(invoice: invoice) }
        .to change { bundle.reload.passes_remaining }.from(2).to(0)

      rows = bundle.redemptions.where(kind: "admin_burn")
      expect(rows.count).to eq(2)
      expect(rows.pluck(:guest_name)).to all(include(invoice.id.to_s))
      expect(rows.pluck(:performed_by_id)).to all(be_nil)
    end

    it "takes the pack out of the redeemable scope so the door no longer burns it" do
      make_bundle
      described_class.call(invoice: invoice)

      expect(user.day_pass_bundles.active).to be_empty
      result = Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      expect(result.outcome).to eq(:no_bundle)
    end

    it "leaves already-burned days as usage history" do
      bundle = make_bundle(remaining: 1)
      burned_day = create(:day_pass,
                          user: user, billable: user, operator: operator, location: location,
                          day_pass_type: pack_type, day: Date.current - 2, invoice: nil)
      entry = bundle.redemptions.create!(operator: operator, kind: "entry", performed_by: user,
                                         day_pass: burned_day, redeemed_at: 2.days.ago)

      described_class.call(invoice: invoice)

      expect(bundle.reload.passes_remaining).to eq(0)
      expect(DayPassBundleRedemption.exists?(entry.id)).to be(true)
      expect(DayPass.exists?(burned_day.id)).to be(true)
    end

    it "does not touch a pack tied to a different invoice" do
      other_invoice = create(:invoice, operator: operator, location: location, billable: user)
      other = make_bundle(on_invoice: other_invoice)

      described_class.call(invoice: invoice)

      expect(other.reload.passes_remaining).to eq(2)
    end

    it "enqueues no lifecycle emails (a refunded buyer gets no replenishment nudge)" do
      make_bundle
      expect { described_class.call(invoice: invoice) }
        .not_to have_enqueued_job(SendProductEmailJob)
    end

    it "is idempotent — a second call adds no ledger rows" do
      bundle = make_bundle
      described_class.call(invoice: invoice)

      expect { described_class.call(invoice: invoice) }
        .not_to change { bundle.redemptions.count }
    end
  end

  # Headline regression: the reported clash.
  describe "bundle-redeem clash" do
    it "stops a refunded pass from masking bundle redemption once rescinded" do
      bundle = create(:day_pass_bundle,
                      user: user, operator: operator, location: location,
                      day_pass_type: day_pass_type, passes_remaining: 5)
      make_pass(day: Date.current) # the refunded-but-still-present ghost pass

      # Before rescind: the ghost pass makes the system think the user is covered,
      # so ConsumeOnEntry refuses to burn a bundle pass.
      before = Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
      expect(before.outcome).to eq(:already_covered)

      described_class.call(invoice: invoice)

      # After rescind: no ghost coverage row, so a real bundle redemption proceeds.
      expect(user.day_passes.for_location(location).for_day(Date.current).exists?).to be(false)
      after = nil
      expect { after = Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location) }
        .to change { bundle.reload.passes_remaining }.from(5).to(4)
      expect(after.outcome).to eq(:redeemed)
    end
  end
end
