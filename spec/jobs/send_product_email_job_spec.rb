require "rails_helper"

RSpec.describe SendProductEmailJob, type: :job do
  let(:operator)  { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:user)      { create(:user, operator: operator, current_location: location) }
  let(:pack_type) { create(:day_pass_type, operator: operator, location: location, quantity: 5, name: "5-Pack") }
  # passes_remaining: 0 deliberately — exercises that the review/replenishment
  # paths are not suppressed by the bundle's active? (passes-left) state.
  let(:bundle) do
    create(:day_pass_bundle, user: user, day_pass_type: pack_type, operator: operator,
                             location: location, passes_remaining: 0)
  end

  def enable_template(email_type)
    template = ProductEmailTemplate.find_or_initialize_by(
      operator: operator, location: location,
      product_type: "day_pass_bundle", email_type: email_type
    )
    template.update!(subject: "Subj", body: "<p>Hi {{first_name}}, {{passes_remaining}} left</p>", enabled: true)
    template
  end

  before do
    allow(SpamGuard).to receive(:eligible?).and_return(true)
    ActionMailer::Base.default_url_options[:host] = "test.example.com"
  end

  it "sends the replenishment email for a bundle and logs the send" do
    enable_template("replenishment")
    expect {
      described_class.perform_now("DayPassBundle", bundle.id, operator.id, "day_pass_bundle", "replenishment", user.id)
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
      .and change { ProductEmailSend.where(sendable: bundle, email_type: "replenishment", status: "sent").count }.by(1)
  end

  it "sends the review (follow_up) email even when the bundle has no passes left (a 2-pack emptied on first visit)" do
    enable_template("follow_up")
    expect {
      described_class.perform_now("DayPassBundle", bundle.id, operator.id, "day_pass_bundle", "follow_up", user.id)
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end
