require "test_helper"

# ChargeDayPassInvoice skips out-of-band billables, so an OOB invoice must
# auto-advance or it sits in Stripe draft forever and is never sent
# (TLH, Chris Carney, 9/2026). In-band stays manual: we finalize + pay
# synchronously.
class DayPassable::InvoiceArgsTest < ActiveSupport::TestCase
  def day_pass
    billable = Object.new
    def billable.stripe_customer_id_for_location(_location) = "cus_test"
    OpenStruct.new(billable: billable, location: nil)
  end

  test "out-of-band invoices auto-advance and are sent with 30 days to pay" do
    args = DayPassable::OutOfBand.new(day_pass).invoice_args
    assert_equal true, args[:auto_advance]
    assert_equal "send_invoice", args[:billing]
    assert_equal 30, args[:days_until_due]
  end

  test "in-band invoices do not auto-advance (charged synchronously)" do
    args = DayPassable::InBand.new(day_pass).invoice_args
    assert_equal false, args[:auto_advance]
    assert_equal "charge_automatically", args[:billing]
  end
end
