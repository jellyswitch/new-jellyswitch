require "rails_helper"

# Phase 2 cancellation/refund policy (ADR 0011) on the unified pipeline.
RSpec.describe CancelReservation do
  let(:operator) { create(:operator, billing_state: "production", cancellation_window_hours: 24, refund_fee_percent: 10) }
  let(:location) { create(:location, operator: operator) }
  let(:room) { create(:room, operator: operator, location: location, hourly_rate_in_cents: 5000) }
  let(:user) { create(:user, operator: operator) }

  before { ActsAsTenant.current_tenant = operator }
  after { ActsAsTenant.current_tenant = nil }

  def reservation_at(hours_from_now)
    r = Reservation.new(
      room: room, user: user, datetime_in: hours_from_now.hours.from_now, minutes: 60,
      captured_amount_in_cents: 5000, captured_at: Time.current, paid: true,
      stripe_payment_intent_id: "pi_booking",
    )
    r.save!(validate: false)
    r
  end

  def paid_invoice(reservation, pi:, amount: 5000)
    create(:invoice, operator: operator, location: location, billable: user,
                     reservation: reservation, status: "paid", amount_due: amount,
                     amount_paid: amount, stripe_payment_intent_id: pi)
  end

  # Capture which invoices the pipeline was asked to refund (the adapter
  # delegates #id to the wrapped invoice). Isolates this interactor's policy
  # decision from the refund mechanics (covered by their own specs).
  def stub_refunds!
    refunded = []
    allow(Billing::Invoices::Refunds::Create).to receive(:call) do |args|
      refunded << args[:invoice].id
      double("result", success?: true)
    end
    refunded
  end

  it "outside the window refunds ALL of the reservation's invoices" do
    r = reservation_at(48) # outside the 24h window
    booking = paid_invoice(r, pi: "pi_booking")
    extension = paid_invoice(r, pi: "pi_ext", amount: 2000)
    refunded = stub_refunds!

    result = described_class.call(reservation: r, mode: :member)

    expect(result).to be_a_success
    expect(r.reload.cancelled?).to be(true)
    expect(refunded).to contain_exactly(booking.id, extension.id)
  end

  it "inside the window forfeits — no refund, charge stands" do
    r = reservation_at(2) # inside the 24h window
    paid_invoice(r, pi: "pi_booking")
    expect(Billing::Invoices::Refunds::Create).not_to receive(:call)

    result = described_class.call(reservation: r, mode: :member)

    expect(result).to be_a_success
    expect(r.reload.cancelled?).to be(true)
  end

  it "admin mode refunds even inside the window (operator-forced cancel)" do
    r = reservation_at(2) # inside the window
    booking = paid_invoice(r, pi: "pi_booking")
    refunded = stub_refunds!

    described_class.call(reservation: r, mode: :admin)

    expect(refunded).to contain_exactly(booking.id)
  end

  it "demo operator issues no real refund" do
    ActsAsTenant.current_tenant = nil
    demo_operator = create(:operator, billing_state: "demo", cancellation_window_hours: 24, refund_fee_percent: 10)
    ActsAsTenant.with_tenant(demo_operator) do
      demo_location = create(:location, operator: demo_operator)
      demo_room = create(:room, operator: demo_operator, location: demo_location, hourly_rate_in_cents: 5000)
      demo_user = create(:user, operator: demo_operator)
      r = Reservation.new(room: demo_room, user: demo_user, datetime_in: 48.hours.from_now, minutes: 60,
                          captured_amount_in_cents: 0, captured_at: Time.current)
      r.save!(validate: false)
      create(:invoice, operator: demo_operator, location: demo_location, billable: demo_user,
                       reservation: r, status: "paid", amount_due: 5000)
      expect(Billing::Invoices::Refunds::Create).not_to receive(:call)

      result = described_class.call(reservation: r, mode: :admin)
      expect(result).to be_a_success
    end
  end

  it "is idempotent — an already-cancelled reservation issues no refund" do
    r = reservation_at(48)
    paid_invoice(r, pi: "pi_booking")
    r.update_column(:cancelled, true)
    expect(Billing::Invoices::Refunds::Create).not_to receive(:call)

    result = described_class.call(reservation: r, mode: :member)
    expect(result).to be_a_success
  end

  it "survives an already-refunded invoice in the set (NotRefundable null-object)" do
    r = reservation_at(48)
    good = paid_invoice(r, pi: "pi_booking")
    # A void invoice → RefundableFactory returns NotRefundable, whose #cancel is
    # a no-op; the loop must not crash. Use the real pipeline for this one.
    create(:invoice, operator: operator, location: location, billable: user,
                     reservation: r, status: "void", amount_due: 5000)
    allow_any_instance_of(Refundable::RefundableInvoice).to receive(:cancel).and_return(true)

    expect { described_class.call(reservation: r, mode: :admin) }.not_to raise_error
    expect(r.reload.cancelled?).to be(true)
  end
end
