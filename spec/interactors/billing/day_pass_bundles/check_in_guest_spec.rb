require "rails_helper"
RSpec.describe Billing::DayPassBundles::CheckInGuest do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }
  def bundle(remaining: 5, expires_at: nil)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: location,
                          day_pass_type: type, quantity_purchased: 5, passes_remaining: remaining,
                          expires_at: expires_at, purchased_at: Time.current)
  end

  it "burns one pass as a guest redemption with the guest name" do
    b = bundle
    expect { described_class.call(bundle: b, performed_by: user, guest_name: "Sam") }
      .to change { b.reload.passes_remaining }.from(5).to(4)
    r = b.redemptions.order(:id).last
    expect(r.kind).to eq("guest")
    expect(r.guest_name).to eq("Sam")
    expect(r.performed_by).to eq(user)
    expect(r.day_pass).to be_nil
  end

  it "fails when the bundle has no passes left" do
    b = bundle(remaining: 0)
    ctx = described_class.call(bundle: b, performed_by: user, guest_name: "Sam")
    expect(ctx).to be_failure
    expect(b.reload.passes_remaining).to eq(0)
  end

  it "fails when the bundle is expired" do
    b = bundle(expires_at: 1.day.ago)
    ctx = described_class.call(bundle: b, performed_by: user, guest_name: "Sam")
    expect(ctx).to be_failure
  end

  it "allows a blank guest name" do
    b = bundle
    ctx = described_class.call(bundle: b, performed_by: user)
    expect(ctx).to be_success
    expect(b.reload.passes_remaining).to eq(4)
  end
end
