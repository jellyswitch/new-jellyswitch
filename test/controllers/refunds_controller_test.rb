require 'test_helper'

# Refunding a paid invoice: POST /invoices/:invoice_id/refunds.
#
# Both tests here were commented out in 2023 ("pass locally but not on github
# actions") and the controller has had no request coverage since — while the
# refund path went on to produce four separate production bugs: the day-pass
# refund that didn't rescind the pass (#581), the bundle refund that didn't
# zero the pack (#723), and the reconcile/webhook divergence pair (#548/#549).
#
# The originals stubbed Stripe at the HTTP wire with WebMock, which is what made
# them environment-dependent. These stub the Stripe boundary itself
# (Location#create_stripe_refund), so what's under test is our behavior —
# invoice state, the refund row, the feed card, and the already-refunded
# guard — not Stripe's wire format.
class RefundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @invoice  = invoices(:paid_invoice)
    @admin.update!(current_location: @location, original_location: @location)

    # Whatever Stripe would have returned for the refund.
    @stripe_refund = Struct.new(:id).new("re_test_refund")
    Location.any_instance.stubs(:create_stripe_refund).returns(@stripe_refund)

    # Creating the feed card broadcasts it, which renders _refund_feed_item ->
    # Invoice#description -> Stripe. That lookup is what made the original
    # version of this file environment-dependent: its `rescue` doesn't catch
    # WebMock's error (not a StandardError), so a blocked call escapes instead
    # of falling back to "Invoice #123" the way a real Stripe failure would.
    Invoice.any_instance.stubs(:stripe_invoice).returns(nil)

    log_in @admin
  end

  def refund_feed_items
    FeedItem.where(operator: @operator)
            .where("blob->>'type' = ?", 'refund')
            .where("blob->>'invoice_id' = ?", @invoice.id.to_s)
  end

  test "refunding a paid invoice marks it refunded and records the refund" do
    post invoice_refunds_path(invoice_id: @invoice.id), env: default_env
    assert_redirected_to invoices_path

    @invoice.reload
    assert_equal 'refunded', @invoice.status
    assert_not_nil @invoice.refunded_at
    assert_equal @invoice.amount_due, @invoice.refund_amount_in_cents
    assert_equal "re_test_refund", @invoice.refunds.last&.stripe_refund_id
  end

  test "the refund posts a feed card at the invoice's location" do
    assert_difference -> { refund_feed_items.count }, +1 do
      post invoice_refunds_path(invoice_id: @invoice.id), env: default_env
    end

    assert_equal @location, refund_feed_items.last.location,
      "a refund card must land at the location that took the money"
  end

  test "refunding from the iOS webview behaves the same" do
    post invoice_refunds_path(invoice_id: @invoice.id), env: ios_env
    assert_redirected_to invoices_path
    assert_equal 'refunded', @invoice.reload.status
  end

  test "an already-refunded invoice is refused, not refunded twice" do
    post invoice_refunds_path(invoice_id: @invoice.id), env: default_env
    assert_equal 'refunded', @invoice.reload.status
    refunds_after_first = @invoice.refunds.count

    # Second attempt: RefundableFactory now resolves to NotRefundable.
    assert_no_difference -> { refund_feed_items.count } do
      post invoice_refunds_path(invoice_id: @invoice.id), env: default_env
    end

    assert_equal refunds_after_first, @invoice.reload.refunds.count,
      "a second refund must not create another refund row"
    assert flash[:error].present?, "the operator must be told why nothing happened"
  end

  test "the operator's retention percentage is withheld from the refund" do
    @operator.update!(refund_fee_percent: 3)

    post invoice_refunds_path(invoice_id: @invoice.id), env: default_env

    @invoice.reload
    expected = @invoice.amount_due - (@invoice.amount_due * 0.03).round
    assert_equal expected, @invoice.refund_amount_in_cents,
      "Stripe keeps its fee on the original charge, so the operator's retention policy applies"
  end
end
