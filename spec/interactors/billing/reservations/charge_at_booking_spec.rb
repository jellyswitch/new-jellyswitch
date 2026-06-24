require "rails_helper"

RSpec.describe Billing::Reservations::ChargeAtBooking do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:paid_room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000, rentable: true) }
  let(:user) { create(:user, operator: operator) }

  def reservation_for(u: user, room: paid_room, minutes: 60)
    r = Reservation.new(room: room, user: u, datetime_in: 2.days.from_now.change(hour: 12), minutes: minutes)
    r.save!(validate: false)
    r
  end

  def stub_card!(pi_id: "pi_test")
    user.update_stripe_customer_id_for_location(location, "cus_test")
    allow(Stripe::Customer).to receive(:retrieve).and_return(double("cust", default_source: "card_1"))
    allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: pi_id))
  end

  describe "self-serve immediate capture" do
    it "captures the charge, marks paid + captured_at, writes a paid Invoice with reservation_id" do
      stub_card!
      r = reservation_for
      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      r.reload
      expect(r.paid).to be(true)
      expect(r.captured_at).to be_present
      expect(r.captured_amount_in_cents).to eq(5000)
      expect(r.stripe_payment_intent_id).to eq("pi_test")
      inv = r.invoices.first
      expect(inv).to be_present
      expect(inv.status).to eq("paid")
      expect(inv.amount_due).to eq(5000)
      expect(inv.stripe_payment_intent_id).to eq("pi_test")
    end

    it "passes a deterministic idempotency key to Stripe" do
      stub_card!
      r = reservation_for
      described_class.call(reservation: r)
      expect(Stripe::PaymentIntent).to have_received(:create).with(
        hash_including(amount: 5000),
        hash_including(idempotency_key: "resv-#{r.id}-charge-5000"),
      )
    end

    it "dispatches a member-facing charge push on capture (Phase 6)" do
      stub_card!
      r = reservation_for
      expect(SendNotificationsJob).to receive(:perform_later).with(r, "ReservationCharged")
      described_class.call(reservation: r)
    end

    it "is idempotent — a second call does not charge again" do
      stub_card!
      r = reservation_for
      described_class.call(reservation: r)
      described_class.call(reservation: r.reload)
      expect(Stripe::PaymentIntent).to have_received(:create).once
    end

    it "fails the booking on a card decline and does NOT stamp captured_at" do
      user.update_stripe_customer_id_for_location(location, "cus_test")
      allow(Stripe::Customer).to receive(:retrieve).and_return(double("cust", default_source: "card_1"))
      allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::CardError.new("Your card was declined.", nil))
      r = reservation_for

      result = described_class.call(reservation: r)

      expect(result).to be_a_failure
      r.reload
      expect(r.captured_at).to be_nil
      expect(r.invoices).to be_empty
    end
  end

  describe "net-30 (out_of_band) org → send_invoice" do
    it "sends a Stripe invoice, writes an open Invoice with reservation_id, captures no money" do
      user.update_column(:out_of_band, true) # bypass unrelated payment-profile validation in setup
      user.update_stripe_customer_id_for_location(location, "cus_net30")
      allow(Stripe::InvoiceItem).to receive(:create).and_return(double("ii", id: "ii_1"))
      allow(Stripe::Invoice).to receive(:create).and_return(double("inv", id: "in_1"))
      expect(Stripe::PaymentIntent).not_to receive(:create)
      # No member charge push on the net-30 path — Stripe emails its own invoice.
      expect(SendNotificationsJob).not_to receive(:perform_later)

      r = reservation_for
      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      r.reload
      expect(r.captured_at).to be_present
      expect(r.captured_amount_in_cents).to eq(0)
      inv = r.invoices.first
      expect(inv.status).to eq("open")
      expect(inv.stripe_invoice_id).to eq("in_1")
      expect(inv.due_date).to be_present
    end
  end

  describe "no money moves" do
    it "demo operator → no charge, no invoice" do
      demo_operator = create(:operator, billing_state: "demo")
      demo_location = create(:location, operator: demo_operator)
      demo_room = create(:room, operator: demo_operator, location: demo_location, hourly_rate_in_cents: 5000, rentable: true)
      demo_user = create(:user, operator: demo_operator)
      r = Reservation.new(room: demo_room, user: demo_user, datetime_in: 2.days.from_now.change(hour: 12), minutes: 60)
      r.save!(validate: false)
      expect(Stripe::PaymentIntent).not_to receive(:create)

      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      expect(r.reload.captured_at).to be_nil
      expect(r.invoices).to be_empty
    end

    # The day-pass overage branch in ChargeCalculator is NOT billing_state-gated,
    # so it can return a positive amount even for a demo operator. ChargeAtBooking
    # must still move no money (the demo gate covers every path).
    it "demo operator with a metered day-pass overage → still no charge" do
      demo_operator = create(:operator, billing_state: "demo")
      ActsAsTenant.with_tenant(demo_operator) do
        demo_location = create(:location, operator: demo_operator, overage_rate_in_cents: 1200)
        demo_room = create(:room, operator: demo_operator, location: demo_location, hourly_rate_in_cents: 0)
        demo_user = create(:user, operator: demo_operator)
        dpt = create(:day_pass_type, operator: demo_operator, location: demo_location,
                     included_meeting_room_minutes: 30, overage_rate_in_cents: 9999)
        r = Reservation.new(room: demo_room, user: demo_user, datetime_in: 2.days.from_now.change(hour: 12), minutes: 60)
        r.save!(validate: false)
        create(:day_pass, user: demo_user, billable: demo_user, operator: demo_operator,
                          location: demo_location, day_pass_type: dpt, day: r.datetime_in.to_date)
        # ChargeCalculator WOULD bill the overage (branch isn't billing_state-gated)...
        expect(Billing::Reservations::ChargeCalculator.call(reservation: r, minutes: 60)).to be > 0
        # ...but ChargeAtBooking's demo gate prevents any real charge.
        expect(Stripe::PaymentIntent).not_to receive(:create)

        result = described_class.call(reservation: r)

        expect(result).to be_a_success
        expect(r.reload.captured_at).to be_nil
        expect(r.invoices).to be_empty
      end
    end

    it "exempt member → no charge" do
      member = create(:user, operator: operator)
      plan = create(:plan, operator: operator, location: location, amount_in_cents: 30000)
      create(:subscription, subscribable: member, plan: plan, active: true, paused: false)
      r = reservation_for(u: member)
      expect(Stripe::PaymentIntent).not_to receive(:create)

      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      expect(r.reload.captured_at).to be_nil
    end

    # The exemption (ChargeCalculator → should_charge_for_room?) runs BEFORE the
    # out_of_band branch, so a net-30 booker who is ALSO a member or leaseholder
    # is still exempt — they are never send_invoice'd for a room.
    it "out_of_band member → no charge, no send_invoice" do
      member = create(:user, operator: operator)
      plan = create(:plan, operator: operator, location: location, amount_in_cents: 30000)
      create(:subscription, subscribable: member, plan: plan, active: true, paused: false)
      member.update_column(:out_of_band, true)
      r = reservation_for(u: member)
      expect(Stripe::PaymentIntent).not_to receive(:create)
      expect(Stripe::Invoice).not_to receive(:create)
      expect(Stripe::InvoiceItem).not_to receive(:create)

      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      r.reload
      expect(r.captured_at).to be_nil
      expect(r.invoices).to be_empty
    end

    it "out_of_band leaseholder → no charge, no send_invoice" do
      leaseholder = create(:user, operator: operator)
      create(:office_lease, user: leaseholder, organization: nil, operator: operator, location: location)
      leaseholder.update_column(:out_of_band, true)
      expect(leaseholder.has_active_lease?).to be(true)
      r = reservation_for(u: leaseholder)
      expect(Stripe::PaymentIntent).not_to receive(:create)
      expect(Stripe::Invoice).not_to receive(:create)
      expect(Stripe::InvoiceItem).not_to receive(:create)

      result = described_class.call(reservation: r)

      expect(result).to be_a_success
      r.reload
      expect(r.captured_at).to be_nil
      expect(r.invoices).to be_empty
    end
  end
end
