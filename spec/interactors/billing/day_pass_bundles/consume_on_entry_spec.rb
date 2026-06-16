require "rails_helper"

RSpec.describe Billing::DayPassBundles::ConsumeOnEntry do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
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

  it "is idempotent — a second entry the same day does NOT burn again" do
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
end
