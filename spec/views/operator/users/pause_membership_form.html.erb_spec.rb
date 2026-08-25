require "rails_helper"

# The web pause form is currently dormant — every render of this partial is
# commented out, so the app is the only live pause path. The guard lives here
# anyway so re-enabling the form can't quietly reintroduce an unwarned pause.
RSpec.describe "operator/users/_pause_membership_form", type: :view do
  let(:location) { instance_double("Location", pause_warning: warning) }
  let(:plan)     { instance_double("Plan", location: location) }
  let(:subscription) do
    instance_double("Subscription", plan: plan, to_param: "42", id: 42)
  end

  before do
    allow(view).to receive(:pause_membership_path).and_return("/pause_membership/42")
  end

  context "when the location has a pause warning" do
    let(:warning) { "Heads up! Pausing means giving up your desk." }

    it "makes the member confirm it before the form submits" do
      render partial: "operator/users/pause_membership_form", locals: { subscription: subscription }

      expect(rendered).to include("data-turbo-confirm")
      expect(rendered).to include("Heads up! Pausing means giving up your desk.")
    end
  end

  context "when the location has no pause warning" do
    let(:warning) { nil }

    it "submits without a confirmation, exactly as before" do
      render partial: "operator/users/pause_membership_form", locals: { subscription: subscription }

      expect(rendered).not_to include("data-turbo-confirm")
      expect(rendered).to include("Pause Membership")
    end
  end

  context "when the warning is only whitespace" do
    let(:warning) { "   " }

    it "does not raise an empty confirmation dialog" do
      render partial: "operator/users/pause_membership_form", locals: { subscription: subscription }

      expect(rendered).not_to include("data-turbo-confirm")
    end
  end
end
