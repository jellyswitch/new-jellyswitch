require "rails_helper"

RSpec.describe DayPassBundle do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }

  def bundle(attrs = {})
    DayPassBundle.create!({ user: user, billable: user, operator: operator, location: location,
                            day_pass_type: type, quantity_purchased: 5, passes_remaining: 5,
                            purchased_at: Time.current }.merge(attrs))
  end

  it "is active when it has passes and is not expired" do
    expect(bundle).to be_active
  end

  it "is not active when passes are exhausted" do
    expect(bundle(passes_remaining: 0)).not_to be_active
  end

  it "is expired (and inactive) when expires_at is in the past" do
    b = bundle(expires_at: 1.day.ago)
    expect(b).to be_expired
    expect(b).not_to be_active
  end

  it "is not expired when expires_at is nil (perpetual)" do
    expect(bundle(expires_at: nil)).not_to be_expired
  end

  it "scopes .active to non-empty, non-expired bundles" do
    live = bundle
    bundle(passes_remaining: 0)
    bundle(expires_at: 1.day.ago)
    expect(DayPassBundle.active).to contain_exactly(live)
  end

  describe "#burn! / #restore!" do
    it "burn! decrements and logs a redemption of the given kind" do
      b = bundle(passes_remaining: 3)
      expect { b.burn!(kind: :guest, performed_by: user, guest_name: "Sam") }
        .to change { b.reload.passes_remaining }.from(3).to(2)
      r = b.redemptions.last
      expect(r.kind).to eq("guest")
      expect(r.guest_name).to eq("Sam")
      expect(r.performed_by).to eq(user)
    end

    it "burn! raises and does not go negative when empty" do
      b = bundle(passes_remaining: 0)
      expect { b.burn!(kind: :entry, performed_by: user) }.to raise_error(DayPassBundle::NoPassesRemaining)
      expect(b.reload.passes_remaining).to eq(0)
    end

    it "burn! raises and does not decrement when the bundle is expired" do
      b = bundle(passes_remaining: 3, expires_at: 1.day.ago)
      expect { b.burn!(kind: :entry, performed_by: user) }.to raise_error(DayPassBundle::NoPassesRemaining)
      expect(b.reload.passes_remaining).to eq(3)
    end

    it "restore! increments and logs an admin_restore" do
      b = bundle(passes_remaining: 1)
      admin = create(:user, operator: operator)
      expect { b.restore!(by: admin, reason: "accidental") }
        .to change { b.reload.passes_remaining }.from(1).to(2)
      expect(b.redemptions.last.kind).to eq("admin_restore")
    end
  end
end
