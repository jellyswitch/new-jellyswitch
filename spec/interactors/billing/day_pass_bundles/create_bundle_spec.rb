require "rails_helper"

RSpec.describe Billing::DayPassBundles::CreateBundle do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  # out_of_band: true on the user means billable.out_of_band? == true, which
  # short-circuits ChargeBundleInvoice (same pattern as ChargeDayPassInvoice).
  # We also stub the Stripe calls inside CreateStripeInvoiceForBundle so the
  # spec never hits the network.
  # The user needs a stripe_customer_id even for out_of_band so SaveBundle's
  # billing check passes (mirrors SaveDayPass behaviour exactly).
  let(:user) do
    create(:user, operator: operator, out_of_band: true).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_test_bundle_123")
    end
  end
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5, amount_in_cents: 10_000) }

  before do
    fake_stripe_inv = double("stripe_invoice",
      id: "in_test_bundle_1",
      customer: "cus_test_bundle_123",
      amount_due: 10_000,
      amount_paid: 0,
      number: "INV-001",
      created: Time.current.to_i,
      due_date: nil,
      status: "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_1"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_stripe_inv)
    # Stub CreateInvoice so we don't need a live Stripe customer in the DB
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable: user,
        operator_id: operator.id,
        amount_due: 10_000,
        amount_paid: 0,
        stripe_invoice_id: "in_test_bundle_1",
        date: Time.current,
        status: "draft",
        location_id: location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end
  end

  it "creates one bundle with passes_remaining == quantity and mints no DayPass (out_of_band)" do
    expect {
      ctx = described_class.call(
        params: { day_pass_type: type.id },
        user_id: user.id, operator: operator, location: location, out_of_band: true,
      )
      expect(ctx).to be_success
      expect(ctx.day_pass_bundle.passes_remaining).to eq(5)
      expect(ctx.day_pass_bundle.quantity_purchased).to eq(5)
      expect(ctx.day_pass_bundle.billable).to eq(user)
    }.to change(DayPassBundle, :count).by(1).and change(DayPass, :count).by(0)
  end

  it "sets expires_at from the product's expires_after_days when present" do
    nv_loc = create(:location, operator: operator, state: "NV")
    nv_user = create(:user, operator: operator, out_of_band: true).tap do |u|
      u.update_stripe_customer_id_for_location(nv_loc, "cus_test_bundle_nv")
    end
    t = create(:day_pass_type, operator: operator, location: nv_loc, quantity: 5, amount_in_cents: 10_000, expires_after_days: 30)
    ctx = described_class.call(params: { day_pass_type: t.id }, user_id: nv_user.id, operator: operator, location: nv_loc, out_of_band: true)
    expect(ctx).to be_success
    expect(ctx.day_pass_bundle.expires_at).to be_within(1.minute).of(Time.current + 30.days)
  end

  it "leaves expires_at nil (perpetual) when the product has no expiry policy" do
    ctx = described_class.call(params: { day_pass_type: type.id }, user_id: user.id, operator: operator, location: location, out_of_band: true)
    expect(ctx).to be_success
    expect(ctx.day_pass_bundle.expires_at).to be_nil
  end
end

RSpec.describe Billing::DayPassBundles::UpdatePaymentAndCreateBundle do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  # First-time buyer: NO stripe customer for the location yet, no out_of_band.
  # UpdateUserPayment (stubbed) creates the customer; we mirror that by calling
  # update_stripe_customer_id_for_location inside the stub, exactly as
  # create_or_update_customer_payment does in production.
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5, amount_in_cents: 10_000) }

  before do
    # Stub UpdateUserPayment: succeed and materialise a Stripe customer on the
    # user for this location so CreateStripeInvoiceForBundle can bill them.
    # Organizers invoke sub-interactors via .call!(context), so stub call!.
    # SaveBundle runs first and sets context.user; stub reads it from context.
    allow(Billing::Payment::UpdateUserPayment).to receive(:call!) do |ctx|
      ctx.user.update_stripe_customer_id_for_location(ctx.location, "cus_token_buyer_123")
    end

    fake_stripe_inv = double("stripe_invoice",
      id: "in_test_token_bundle_1",
      customer: "cus_token_buyer_123",
      amount_due: 10_000,
      amount_paid: 0,
      number: "INV-T001",
      created: Time.current.to_i,
      due_date: nil,
      status: "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_t1"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_stripe_inv)
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable: user,
        operator_id: operator.id,
        amount_due: 10_000,
        amount_paid: 0,
        stripe_invoice_id: "in_test_token_bundle_1",
        date: Time.current,
        status: "draft",
        location_id: location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end
    # Stub ChargeBundleInvoice (via ChargeInvoice) to avoid hitting Stripe network.
    # Mirrors the approach in spec/requests/api/v1/day_pass_bundle_purchase_spec.rb.
    allow(Billing::Invoices::ChargeInvoice).to receive(:call).and_return(
      OpenStruct.new(success?: true)
    )
  end

  it "creates a bundle for a first-time buyer who provides a card token" do
    ctx = described_class.call(
      params: { day_pass_type: type.id }, user_id: user.id,
      operator: operator, location: location, token: "tok_visa"
    )
    expect(ctx).to be_success
    expect(ctx.day_pass_bundle.passes_remaining).to eq(type.quantity)
  end
end
