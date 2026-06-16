require "rails_helper"

RSpec.describe "Bundle purchase notifications" do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) do
    create(:user, operator: operator, out_of_band: true).tap do |u|
      u.update_stripe_customer_id_for_location(location, "cus_test_notif_123")
    end
  end
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5, amount_in_cents: 10_000) }

  before do
    fake_stripe_inv = double("stripe_invoice",
      id: "in_test_notif_1",
      customer: "cus_test_notif_123",
      amount_due: 10_000,
      amount_paid: 0,
      number: "INV-NOTIF-001",
      created: Time.current.to_i,
      due_date: nil,
      status: "draft"
    )
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double("item", id: "ii_notif_1"))
    allow(Stripe::Invoice).to receive(:create).and_return(fake_stripe_inv)
    allow(CreateInvoice).to receive(:call) do |_args|
      inv = Invoice.create!(
        billable: user,
        operator_id: operator.id,
        amount_due: 10_000,
        amount_paid: 0,
        stripe_invoice_id: "in_test_notif_1",
        date: Time.current,
        status: "draft",
        location_id: location.id
      )
      OpenStruct.new(success?: true, invoice: inv)
    end

    # Stub push transport so we don't need APNs / FCM credentials in tests
    allow_any_instance_of(Notifiable::Default).to receive(:ios)
    allow_any_instance_of(Notifiable::Default).to receive(:android)
  end

  it "creates a feed item for the bundle purchase" do
    expect {
      Billing::DayPassBundles::CreateBundle.call(
        params: { day_pass_type: type.id },
        user_id: user.id,
        operator: operator,
        location: location,
        out_of_band: true
      )
    }.to change(FeedItem, :count).by(1)

    fi = FeedItem.order(:id).last
    expect(fi.blob["type"]).to eq("day-pass-bundle")
    expect(fi.blob["user_name"]).to eq(user.name)
    expect(fi.blob["message"]).to match(/5-Pack/i)
  end

  it "does not break the existing organizer (bundle still saved)" do
    ctx = Billing::DayPassBundles::CreateBundle.call(
      params: { day_pass_type: type.id },
      user_id: user.id,
      operator: operator,
      location: location,
      out_of_band: true
    )
    expect(ctx).to be_success
    expect(ctx.day_pass_bundle).to be_a(DayPassBundle)
    expect(ctx.day_pass_bundle.passes_remaining).to eq(5)
  end
end
