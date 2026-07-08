require "rails_helper"

RSpec.describe Billing::Subscription::SendMembershipWelcome do
  let(:operator)     { create(:operator) }
  let(:location)     { create(:location, operator: operator) }
  let(:user)         { create(:user, operator: operator) }
  let(:plan)         { create(:plan, operator: operator, location: location, amount_in_cents: 20500) }
  let(:subscription) { create(:subscription, plan: plan, subscribable: user, billable: user) }

  before { allow(Honeybadger).to receive(:notify) }

  def run
    described_class.call(subscription: subscription, user: user, operator: operator, location: location)
  end

  it "sends the welcome email to the new member" do
    mail = double(deliver_later: true)
    expect(UserMailer).to receive(:membership_welcome_email)
      .with(user, operator, subscription, location).and_return(mail)
    expect(run).to be_success
  end

  it "does not send when the member has no email" do
    allow(user).to receive(:email).and_return("")
    expect(UserMailer).not_to receive(:membership_welcome_email)
    run
  end

  it "never fails the signup when the email raises (best-effort)" do
    allow(UserMailer).to receive(:membership_welcome_email).and_raise("smtp down")
    expect(run).to be_success
    expect(Honeybadger).to have_received(:notify)
  end

  it "is wired into both new-subscription organizers" do
    expect(Billing::Subscription::CreateSubscription.organized).to include(described_class)
    expect(Billing::Subscription::UpdatePaymentAndCreateSubscription.organized).to include(described_class)
  end
end

RSpec.describe UserMailer, "#membership_welcome_email" do
  let(:operator)     { create(:operator, name: "Test Space") }
  let(:location)     { create(:location, operator: operator) }
  let(:user)         { create(:user, operator: operator, name: "Jamie Member") }
  let(:plan)         { create(:plan, operator: operator, location: location, name: "Flex", amount_in_cents: 20500) }
  let(:subscription) { create(:subscription, plan: plan, subscribable: user, billable: user) }

  it "renders with the space name, plan, and price" do
    mail = described_class.membership_welcome_email(user, operator, subscription, location)
    expect(mail.subject).to eq("Welcome to Test Space")
    body = mail.body.encoded
    expect(body).to include("Flex")
    expect(body).to include("$205.00")
  end

  it "renders a free plan as Free (no price)" do
    plan.update!(amount_in_cents: 0)
    mail = described_class.membership_welcome_email(user, operator, subscription, location)
    expect(mail.body.encoded).to include("Free")
  end
end
