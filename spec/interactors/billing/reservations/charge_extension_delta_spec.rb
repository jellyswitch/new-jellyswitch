require "rails_helper"

RSpec.describe Billing::Reservations::ChargeExtensionDelta, type: :interactor do
  let(:operator) { double("operator", name: "Acme") }
  let(:location) { double("location", stripe_secret_key: "sk_test", stripe_user_id: "acct_1", operator: operator) }
  let(:room) { double("room", location: location, name: "Room A") }
  let(:user) { double("user", out_of_band?: false, stripe_customer_id_for_location: "cus_x", name: "Member") }
  let(:reservation) do
    double("reservation", id: 77, user: user, room: room, minutes: 90,
                          captured_amount_in_cents: 6000, authorized_amount_in_cents: 6000,
                          pretty_datetime: "Mon 1pm")
  end

  before do
    allow(Billing::Reservations::ChargeCalculator).to receive(:call).and_return(9000) # new_total
    allow_any_instance_of(described_class).to receive(:default_payment_method).and_return("pm_x")
    allow(reservation).to receive(:update!)
    # Post-charge bookkeeping (local invoice + feed card) is out of scope here.
    allow(Invoice).to receive(:create!).and_return(double(id: 1))
    allow(FeedItem).to receive(:create!)
  end

  it "places the delta PaymentIntent with an idempotency key keyed on the new total" do
    captured = nil
    allow(Stripe::PaymentIntent).to receive(:create) { |_p, opts| captured = opts; double(id: "pi_x") }

    result = described_class.call(reservation: reservation)

    expect(result).to be_success
    # delta = 9000 - 6000 = 3000; a double-tap recomputing the same new_total
    # reuses this key so Stripe places ONE PaymentIntent.
    expect(captured[:idempotency_key]).to eq("resv-77-ext-9000")
    expect(captured[:api_key]).to eq("sk_test")
  end
end
