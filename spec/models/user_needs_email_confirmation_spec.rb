require "rails_helper"

# Drives the persistent "verify your email" nudge (web layout banner +
# mobile login/me flag) that replaced the hard login block.
RSpec.describe User, "#needs_email_confirmation?", type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  it "is true for an unconfirmed self-signup member" do
    user = build(:user, operator: operator, original_location: location,
                        role: User::UNASSIGNED, email_confirmed: false)
    expect(user.needs_email_confirmation?).to be(true)
  end

  it "is false once the member confirms" do
    user = build(:user, operator: operator, original_location: location,
                        role: User::UNASSIGNED, email_confirmed: true)
    expect(user.needs_email_confirmation?).to be(false)
  end

  it "is false for staff even when unconfirmed (they're never UNASSIGNED)" do
    user = build(:user, operator: operator, original_location: location,
                        role: User::ADMIN, email_confirmed: false)
    expect(user.needs_email_confirmation?).to be(false)
  end
end
