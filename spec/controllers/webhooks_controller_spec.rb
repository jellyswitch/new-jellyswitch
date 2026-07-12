require "rails_helper"

RSpec.describe WebhooksController, type: :controller do
  describe "POST #stripe — charge.succeeded captures home_zip" do
    let(:operator) { create(:operator, stripe_user_id: "acct_TEST_OP") }
    let(:location) { create(:location, operator: operator) }
    let!(:user) { create(:user, operator: operator, current_location: location, stripe_customer_id: "cus_TEST_USER", home_zip: nil) }

    def make_event(postal_code:, customer_id: "cus_TEST_USER", connected_account: "acct_TEST_OP")
      Stripe::Event.construct_from(
        type: "charge.succeeded",
        account: connected_account,
        data: {
          object: {
            id: "ch_TEST",
            customer: customer_id,
            billing_details: { address: { postal_code: postal_code } }
          }
        }
      )
    end

    before do
      allow_any_instance_of(WebhooksController).to receive(:report_error)
    end

    it "writes postal_code to user.home_zip" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: "96150"))
      post :stripe, body: "{}"
      expect(user.reload.home_zip).to eq("96150")
    end

    it "is idempotent — does not overwrite a non-blank home_zip" do
      user.update_column(:home_zip, "94110")
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: "96150"))
      post :stripe, body: "{}"
      expect(user.reload.home_zip).to eq("94110")
    end

    it "no-op when postal_code is missing from the charge" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: nil))
      post :stripe, body: "{}"
      expect(user.reload.home_zip).to be_nil
    end

    it "ignores charges on a connected account we don't own" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: "96150", connected_account: "acct_DIFFERENT_OP"))
      post :stripe, body: "{}"
      expect(user.reload.home_zip).to be_nil
    end

    it "ignores when no user matches the stripe_customer_id" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: "96150", customer_id: "cus_NOBODY"))
      post :stripe, body: "{}"
      expect(user.reload.home_zip).to be_nil
    end

    it "returns 200 OK on success" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(postal_code: "96150"))
      post :stripe, body: "{}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #stripe — charge.refunded reconciles the local invoice" do
    let(:operator) { create(:operator, stripe_user_id: "acct_OP") }
    let(:location) { create(:location, operator: operator) }
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, status: "paid",
             amount_due: 1000, stripe_payment_intent_id: "pi_1")
    end

    def refund_charge_event
      Stripe::Event.construct_from(
        type: "charge.refunded",
        account: "acct_OP",
        data: {
          object: {
            object: "charge",
            id: "ch_1",
            payment_intent: "pi_1",
            amount_refunded: 1000,
            refunds: { object: "list", data: [{ object: "refund", id: "re_1", amount: 1000 }] },
          }
        }
      )
    end

    before { allow_any_instance_of(WebhooksController).to receive(:report_error) }

    it "marks the invoice refunded and returns 200" do
      allow(Stripe::Event).to receive(:construct_from).and_return(refund_charge_event)
      post :stripe, body: "{}"

      expect(response).to have_http_status(:ok)
      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_1")
    end
  end

  describe "POST #stripe — invoice.payment_failed notifies the member" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, billable: user,
                       amount_due: 9900, status: "open", stripe_invoice_id: "in_FAIL_TEST")
    end

    def make_event(invoice_id: "in_FAIL_TEST")
      Stripe::Event.construct_from(
        type: "invoice.payment_failed",
        data: { object: { id: invoice_id, object: "invoice" } }
      )
    end

    before do
      allow_any_instance_of(WebhooksController).to receive(:report_error)
      # Status mirroring is UpdateInvoiceStatus's own concern (covered by its
      # spec) — stub it so this block stays focused on the notification fan-out.
      allow(UpdateInvoiceStatus).to receive(:call).and_return(double(success?: true))
    end

    it "enqueues the recovery email AND the member push" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      expect {
        post :stripe, body: "{}"
      }.to have_enqueued_job(SendPaymentFailedEmailJob).with("in_FAIL_TEST", operator.id)
       .and have_enqueued_job(SendNotificationsJob).with(invoice, "PaymentFailed")
    end

    it "still posts the admin feed item" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      expect(FeedItemCreator).to receive(:create_feed_item)
        .with(operator, location, user, hash_including(type: "payment_failed"))
      post :stripe, body: "{}"
    end

    it "returns 200" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      post :stripe, body: "{}"
      expect(response).to have_http_status(:ok)
    end

    it "no-ops (200, no jobs) when no local invoice matches" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event(invoice_id: "in_UNKNOWN"))
      expect {
        post :stripe, body: "{}"
      }.not_to have_enqueued_job(SendNotificationsJob)
      expect(response).to have_http_status(:ok)
    end

    it "still fans out the member comms when status-mirroring fails" do
      allow(UpdateInvoiceStatus).to receive(:call)
        .and_return(double(success?: false, message: "stripe hiccup"))
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      expect {
        post :stripe, body: "{}"
      }.to have_enqueued_job(SendNotificationsJob).with(invoice, "PaymentFailed")
    end
  end
end
