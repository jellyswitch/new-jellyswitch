require 'test_helper'

class RefundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_request(:get, "https://api.stripe.com/v1/invoices/in_1LWqY4EV6H9PcOfBykUGCa76")
      .to_return(
        status: 200,
        body: { id: 'in_1LWqY4EV6H9PcOfBykUGCa76', charge: "charge1", amount_due: 20 }.to_json,
        headers: {}
      )

    stub_request(:post, "https://api.stripe.com/v1/refunds")
      .to_return(
        status: 200,
        body: { id: 're_1LWqY4EV6H9PcOfBykUGCa76' }.to_json,
        headers: {}
      )

    @user = users(:cowork_tahoe_admin)
    @paid_invoice = invoices(:paid_invoice)
    log_in @user
  end

  teardown do
    WebMock.reset!
  end

  # TODO: re-enable later since they pass locally but not on github actions
  # test "should refund the paid invoice and redirect back to index (web)" do
  #   post invoice_refunds_path(invoice_id: @paid_invoice.id), env: default_env
  #   assert_redirected_to invoices_path

  #   feed_item = FeedItem.last
  #   assert_equal feed_item.location, locations(:cowork_tahoe_location)
  # end

  # test "should refund the paid invoice and redirect back to index (iOS)" do
  #   post invoice_refunds_path(invoice_id: @paid_invoice.id), env: ios_env
  #   assert_redirected_to invoices_path

  #   feed_item = FeedItem.last
  #   assert_equal feed_item.location, locations(:cowork_tahoe_location)
  # end
end
