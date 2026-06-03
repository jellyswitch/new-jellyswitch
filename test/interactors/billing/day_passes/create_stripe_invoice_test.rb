require "test_helper"

# Covers the rollback safety net added to CreateStripeInvoice: when a later
# interactor in the day-pass organizer fails (most commonly ChargeDayPassInvoice
# for a member with no chargeable card), the Stripe invoice created here must
# be cleaned up instead of being stranded as a ghost draft on the connected
# account — but a *paid* invoice must never be touched.
class Billing::DayPasses::CreateStripeInvoiceTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_member)
  end

  def build_interactor(stripe_invoice_id:, local_invoice:)
    context = Interactor::Context.build(location: @location)
    interactor = Billing::DayPasses::CreateStripeInvoice.new(context)
    interactor.instance_variable_set(:@invoice, OpenStruct.new(id: stripe_invoice_id))
    interactor.instance_variable_set(:@local_invoice, local_invoice)
    interactor
  end

  def make_local_invoice(stripe_id:, status:, amount_paid: 0)
    Invoice.create!(
      billable: @user,
      operator_id: @user.operator.id,
      amount_due: 4000,
      amount_paid: amount_paid,
      status: status,
      stripe_invoice_id: stripe_id,
      date: Time.current,
    )
  end

  test "rollback deletes a stranded DRAFT Stripe invoice and destroys the local invoice" do
    local = make_local_invoice(stripe_id: "in_test_draft", status: "draft")
    Stripe::Invoice.stubs(:retrieve).returns(Stripe::Invoice.construct_from(id: "in_test_draft", status: "draft", paid: false))
    Stripe::Invoice.expects(:delete).with("in_test_draft", anything).once
    Stripe::Invoice.expects(:void_invoice).never

    interactor = build_interactor(stripe_invoice_id: "in_test_draft", local_invoice: local)
    assert_difference "Invoice.count", -1 do
      interactor.rollback
    end
  end

  test "rollback voids an OPEN (finalized, unpaid) Stripe invoice" do
    local = make_local_invoice(stripe_id: "in_test_open", status: "open")
    Stripe::Invoice.stubs(:retrieve).returns(Stripe::Invoice.construct_from(id: "in_test_open", status: "open", paid: false))
    Stripe::Invoice.expects(:void_invoice).with("in_test_open", anything).once
    Stripe::Invoice.expects(:delete).never

    interactor = build_interactor(stripe_invoice_id: "in_test_open", local_invoice: local)
    assert_difference "Invoice.count", -1 do
      interactor.rollback
    end
  end

  test "rollback never deletes/voids or destroys a PAID invoice" do
    local = make_local_invoice(stripe_id: "in_test_paid", status: "paid", amount_paid: 4000)
    Stripe::Invoice.stubs(:retrieve).returns(Stripe::Invoice.construct_from(id: "in_test_paid", status: "paid", paid: true))
    Stripe::Invoice.expects(:delete).never
    Stripe::Invoice.expects(:void_invoice).never

    interactor = build_interactor(stripe_invoice_id: "in_test_paid", local_invoice: local)
    assert_no_difference "Invoice.count" do
      interactor.rollback
    end
  end

  test "rollback swallows Stripe errors so the original failure is not masked" do
    local = make_local_invoice(stripe_id: "in_test_err", status: "draft")
    Stripe::Invoice.stubs(:retrieve).raises(Stripe::StripeError.new("boom"))

    interactor = build_interactor(stripe_invoice_id: "in_test_err", local_invoice: local)
    assert_nothing_raised { interactor.rollback }
    # Stripe cleanup failed, but the local invoice is still removed.
    assert_not Invoice.exists?(local.id)
  end

  def teardown
    Invoice.where(stripe_invoice_id: %w[in_test_draft in_test_open in_test_paid in_test_err]).destroy_all
  end
end
