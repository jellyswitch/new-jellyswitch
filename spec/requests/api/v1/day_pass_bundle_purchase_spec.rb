require "rails_helper"

# Auth pattern mirrors spec/requests/api/v1/reservation_amenities_spec.rb.
# Stripe calls are stubbed directly (same approach as
# spec/interactors/billing/leasing/charge_deposit_spec.rb).
RSpec.describe "API v1 day pass bundle purchase", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  # out_of_band: true means ChargeBundleInvoice short-circuits (no real charge).
  # The user also needs a stripe_customer_id so SaveBundle's billing check passes.
  let(:bundle_user) do
    create(:user, operator: operator, out_of_band: true).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_bundle_req_test")
    end
  end

  # card_added: true + stripe_customer means single-pass path can proceed.
  let(:single_user) do
    create(:user, operator: operator, card_added: true).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_single_req_test")
    end
  end

  let!(:bundle_type) do
    create(:day_pass_type, operator: operator, location: location,
           quantity: 5, amount_in_cents: 10_000, available: true, visible: true)
  end

  let!(:single_type) do
    create(:day_pass_type, operator: operator, location: location,
           quantity: 1, amount_in_cents: 2_000, available: true, visible: true)
  end

  def auth_headers_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization" => "Bearer #{token}",
      "X-Operator-Subdomain" => user.operator.subdomain,
    }
  end

  def stub_stripe_for_bundle(user_stripe_id)
    fake_inv = double("stripe_invoice",
      id: "in_bundle_req_001",
      customer: user_stripe_id,
      amount_due: 10_000,
      amount_paid: 0,
      number: "INV-B01",
      created: Time.current.to_i,
      due_date: nil,
      status: "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_b"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_inv)
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable: bundle_user,
        operator_id: operator.id,
        amount_due: 10_000,
        amount_paid: 0,
        stripe_invoice_id: "in_bundle_req_001",
        date: Time.current,
        status: "draft",
        location_id: location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end
  end

  def stub_stripe_for_single(user_stripe_id)
    fake_inv = double("stripe_invoice",
      id: "in_single_req_001",
      customer: user_stripe_id,
      amount_due: 2_000,
      amount_paid: 0,
      number: "INV-S01",
      created: Time.current.to_i,
      due_date: nil,
      status: "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_s"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_inv)
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable: single_user,
        operator_id: operator.id,
        amount_due: 2_000,
        amount_paid: 0,
        stripe_invoice_id: "in_single_req_001",
        date: Time.current,
        status: "draft",
        location_id: location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end
    # ChargeDayPassInvoice calls Billing::Invoices::ChargeInvoice — stub it
    allow(Billing::Invoices::ChargeInvoice).to receive(:call).and_return(
      OpenStruct.new(success?: true)
    )
    # ChargeInvoice also calls invoice.update(status: 'paid') — handled by stub above
  end

  describe "POST /api/v1/day_passes with a quantity:5 bundle type" do
    it "creates a DayPassBundle with passes_remaining 5 and zero DayPass rows" do
      stub_stripe_for_bundle("cus_bundle_req_test")

      expect {
        post "/api/v1/day_passes",
             params: { day_pass_type_id: bundle_type.id },
             headers: auth_headers_for(bundle_user)
      }.to change(DayPassBundle, :count).by(1).and change(DayPass, :count).by(0)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["passes_remaining"]).to eq(5)
      expect(DayPassBundle.last.quantity_purchased).to eq(5)
    end
  end

  describe "POST /api/v1/day_passes with a bundle type + stripe_token (first-time buyer)" do
    # First-time buyer has NO stripe customer for the location.
    # They supply a stripe_token; UpdatePaymentAndCreateBundle should create the
    # customer (stubbed) and succeed — the token bypass in SaveBundle allows the
    # record to be persisted before UpdateUserPayment runs.
    let(:first_time_buyer) { create(:user, operator: operator) }

    before do
      # Stub UpdateUserPayment's call! (organizer path) to materialise a customer.
      allow(Billing::Payment::UpdateUserPayment).to receive(:call!) do |ctx|
        ctx.user.update_stripe_customer_id_for_location(ctx.location, "cus_first_time_buyer")
      end
      stub_stripe_for_bundle("cus_first_time_buyer")
      # Stub ChargeInvoice so no real Stripe network call is made for charging.
      allow(Billing::Invoices::ChargeInvoice).to receive(:call).and_return(
        OpenStruct.new(success?: true)
      )
    end

    it "creates a DayPassBundle for a first-time buyer who supplies a card token" do
      expect {
        post "/api/v1/day_passes",
             params: { day_pass_type_id: bundle_type.id, stripe_token: "tok_visa" },
             headers: auth_headers_for(first_time_buyer)
      }.to change(DayPassBundle, :count).by(1).and change(DayPass, :count).by(0)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
      expect(body["passes_remaining"]).to eq(5)
    end
  end

  describe "POST /api/v1/day_passes with a quantity:1 single type (regression)" do
    it "still creates a DayPass and zero DayPassBundle rows" do
      stub_stripe_for_single("cus_single_req_test")

      expect {
        post "/api/v1/day_passes",
             params: { day_pass_type_id: single_type.id },
             headers: auth_headers_for(single_user)
      }.to change(DayPass, :count).by(1).and change(DayPassBundle, :count).by(0)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
    end
  end
end
