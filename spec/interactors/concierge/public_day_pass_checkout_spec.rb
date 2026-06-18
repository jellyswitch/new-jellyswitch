require "rails_helper"

RSpec.describe Concierge::PublicDayPassCheckout do
  let(:operator)  { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:pass_type) { create(:day_pass_type, operator: operator, location: location, amount_in_cents: 2_500) }

  let(:args) do
    { operator: operator, location: location, day_pass_type: pass_type,
      email: "New@Visitor.com", name: "New Visitor", password: "sup3rsecret", token: "tok_visa" }
  end

  # Stub the reused billing interactors (their own specs cover Stripe).
  def stub_account_creation(user)
    allow(Users::Create).to receive(:call)
      .and_return(double(success?: true, user: user, message: nil))
  end

  def stub_purchase(success:, day_pass: nil, message: nil)
    allow(Billing::DayPasses::UpdatePaymentAndCreateDayPass).to receive(:call)
      .and_return(double(success?: success, day_pass: day_pass, message: message))
  end

  it "creates the account then charges the day pass, reusing the billing chain" do
    user = create(:user, operator: operator)
    day_pass = create(:day_pass, user: user, operator: operator, location: location, day_pass_type: pass_type, day: Date.current)
    stub_account_creation(user)
    stub_purchase(success: true, day_pass: day_pass)

    result = described_class.call(args)

    expect(result).to be_success
    expect(result.user).to eq(user)
    expect(result.day_pass).to eq(day_pass)
    expect(Users::Create).to have_received(:call).with(hash_including(operator: operator, admin_created: false))
    expect(Billing::DayPasses::UpdatePaymentAndCreateDayPass).to have_received(:call)
      .with(hash_including(user_id: user.id, token: "tok_visa", location: location))
  end

  it "routes a bundle SKU (quantity > 1) to the bundle purchase interactor" do
    bundle_type = create(:day_pass_type, operator: operator, location: location, quantity: 5, amount_in_cents: 10_000)
    user = create(:user, operator: operator)
    bundle = create(:day_pass_bundle, user: user, day_pass_type: bundle_type, operator: operator, location: location)
    stub_account_creation(user)
    allow(Billing::DayPassBundles::UpdatePaymentAndCreateBundle).to receive(:call)
      .and_return(double(success?: true, day_pass_bundle: bundle, message: nil))

    result = described_class.call(args.merge(day_pass_type: bundle_type, email: "bundler@x.com"))

    expect(result).to be_success
    expect(result.day_pass_bundle).to eq(bundle)
    expect(Billing::DayPassBundles::UpdatePaymentAndCreateBundle).to have_received(:call)
      .with(hash_including(user_id: user.id, token: "tok_visa"))
  end

  it "refuses (without creating) when the email already has an account" do
    create(:user, operator: operator, email: "new@visitor.com")
    expect(Users::Create).not_to receive(:call)

    result = described_class.call(args)

    expect(result).to be_failure
    expect(result.error).to eq("account_exists")
  end

  it "surfaces a payment error when the charge fails" do
    user = create(:user, operator: operator)
    stub_account_creation(user)
    stub_purchase(success: false, message: "Your card was declined.")

    result = described_class.call(args)

    expect(result).to be_failure
    expect(result.error).to eq("payment")
    expect(result.message).to eq("Your card was declined.")
  end
end
