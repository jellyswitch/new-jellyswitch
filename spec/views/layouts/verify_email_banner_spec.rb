require "rails_helper"

# Proves the persistent "verify your email" nudge surfaces for the members we
# now let in unconfirmed (and stays hidden for everyone else).
RSpec.describe "layouts/_verify_email_banner", type: :view do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  before do
    allow(view).to receive(:logged_in?).and_return(true)
    allow(view).to receive(:current_user).and_return(user)
  end

  context "an unconfirmed self-signup member" do
    let(:user) do
      create(:user, operator: operator, original_location: location,
                    email: "needsverify@example.com",
                    role: User::UNASSIGNED, email_confirmed: false)
    end

    it "renders the nudge with the member's email and a resend button" do
      render
      expect(rendered).to include("Please verify your email")
      expect(rendered).to include("needsverify@example.com")
      expect(rendered).to include("Resend link")
      expect(rendered).to include(resend_confirmation_path)
    end
  end

  context "a confirmed member" do
    let(:user) do
      create(:user, operator: operator, original_location: location,
                    role: User::UNASSIGNED, email_confirmed: true)
    end

    it "renders no nudge" do
      render
      expect(rendered).not_to include("Please verify your email")
      expect(rendered).not_to include("Resend link")
    end
  end
end
