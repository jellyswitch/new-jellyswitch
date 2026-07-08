require "rails_helper"

# Regression: the "Awaiting Approval" wait page detected the member's plan via
# subscriptions.pending, but the web subscribe flow creates the sub as ACTIVE
# (never pending) — so an unapproved-but-subscribed member saw "No plan selected
# yet" and "browse options" looped them back through subscribe. The page now
# recognizes an active subscription too.
#
# Rendering this page in a spec pulls in current_user/current_tenant view
# helpers plus many partials, so — matching the reserve_now_card regression
# pattern in landing_controller_spec — we assert on the template source.
RSpec.describe "operator/landing/wait.html.erb (plan detection)" do
  let(:source) { File.read(Rails.root.join("app/views/operator/landing/wait.html.erb")) }

  it "detects the member's plan from an ACTIVE or pending subscription" do
    expect(source).to match(
      /current_user\.subscriptions\.active\.first\s*\|\|\s*current_user\.subscriptions\.pending\.first/
    )
  end

  it "no longer keys the plan solely on a pending subscription" do
    expect(source).not_to match(/\bpending_sub\b/)
  end

  it "still renders the Plan-selected line and the no-plan fallback" do
    expect(source).to include("Plan selected:")
    expect(source).to include("No plan selected yet")
  end
end
