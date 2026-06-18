require "rails_helper"

RSpec.describe Billing::DayPassBundles::ScheduleBundleEmails do
  let(:operator)  { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:user)      { create(:user, operator: operator, current_location: location) }
  let(:pack_type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }
  let(:bundle) do
    create(:day_pass_bundle, user: user, day_pass_type: pack_type, operator: operator, location: location)
  end

  def enable_template(email_type)
    template = ProductEmailTemplate.find_or_initialize_by(
      operator: operator, location: location,
      product_type: "day_pass_bundle", email_type: email_type
    )
    template.update!(subject: "S", body: "<p>hi {{first_name}}</p>", enabled: true)
    template
  end

  it "enqueues the onboarding email when the onboarding template is enabled" do
    enable_template("onboarding")
    expect {
      described_class.call(day_pass_bundle: bundle, operator: operator)
    }.to have_enqueued_job(SendProductEmailJob)
      .with("DayPassBundle", bundle.id, operator.id, "day_pass_bundle", "onboarding", user.id)
  end

  it "does NOT enqueue the follow_up (review) at purchase — it is event-fired on first burn" do
    enable_template("onboarding")
    enable_template("follow_up")
    expect {
      described_class.call(day_pass_bundle: bundle, operator: operator)
    }.not_to have_enqueued_job(SendProductEmailJob)
      .with(anything, anything, anything, anything, "follow_up", anything)
  end

  it "does not enroll the buyer in the welcome drip (a bundle buyer is a customer, not a lead)" do
    enable_template("onboarding")
    expect {
      described_class.call(day_pass_bundle: bundle, operator: operator)
    }.not_to change { ProductEmailSend.where(email_type: "welcome_drip_enrolled").count }
  end
end
