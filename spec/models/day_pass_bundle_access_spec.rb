require "rails_helper"

RSpec.describe "Day pass bundle building access" do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:other_location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }

  def bundle(loc: location, remaining: 5, expires_at: nil)
    DayPassBundle.create!(user: user, billable: user, operator: operator, location: loc,
                          day_pass_type: type, quantity_purchased: 5, passes_remaining: remaining,
                          expires_at: expires_at, purchased_at: Time.current)
  end

  it "grants access with an active bundle at the location" do
    bundle
    expect(user.has_active_day_pass_bundle?(location)).to be(true)
    expect(user.allowed_in?(location)).to be(true)
  end

  it "does not grant access when the bundle is empty" do
    bundle(remaining: 0)
    expect(user.has_active_day_pass_bundle?(location)).to be(false)
    expect(user.allowed_in?(location)).to be(false)
  end

  it "does not grant access when the bundle is expired" do
    bundle(expires_at: 1.day.ago)
    expect(user.has_active_day_pass_bundle?(location)).to be(false)
  end

  it "does not grant access from a bundle at a different location" do
    bundle(loc: other_location)
    expect(user.has_active_day_pass_bundle?(location)).to be(false)
  end
end
