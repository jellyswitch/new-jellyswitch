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

    # PaymentCutoff drip, step 1: Stripe re-fires payment_failed on every
    # dunning retry (Kara Morison got 4 identical emails, 2026-08) — the member
    # notice goes out exactly once per invoice; retries only refresh the admin
    # feed card. The later warning/suspension steps belong to PaymentCutoffJob.
    it "records the failure notice and does NOT re-send email or push on a retry" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      post :stripe, body: "{}"
      expect(ProductEmailSend.where(sendable: invoice,
                                    email_type: PaymentCutoff::FAILED_NOTICE).count).to eq(1)

      expect {
        expect {
          post :stripe, body: "{}"
        }.not_to have_enqueued_job(SendPaymentFailedEmailJob)
      }.not_to have_enqueued_job(SendNotificationsJob)
      expect(response).to have_http_status(:ok)
      expect(ProductEmailSend.where(sendable: invoice,
                                    email_type: PaymentCutoff::FAILED_NOTICE).count).to eq(1)
    end

    it "still posts the admin feed item on a retry" do
      allow(Stripe::Event).to receive(:construct_from).and_return(make_event)
      post :stripe, body: "{}"
      expect(FeedItemCreator).to receive(:create_feed_item)
        .with(operator, location, user, hash_including(type: "payment_failed"))
      post :stripe, body: "{}"
    end
  end

  describe "POST #stripe — signature verification (staged rollout)" do
    # An unhandled event type falls through to `ok` (200), so these specs can
    # assert on the verification branching without a fixture-heavy handler.
    let(:unhandled_event) { Stripe::Event.construct_from(type: "ping", data: { object: {} }) }

    before { allow_any_instance_of(WebhooksController).to receive(:report_error) }

    def stub_env(secret: nil, test_secret: nil, enforce: nil)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("STRIPE_WEBHOOK_SECRET").and_return(secret)
      allow(ENV).to receive(:[]).with("STRIPE_TEST_WEBHOOK_SECRET").and_return(test_secret)
      allow(ENV).to receive(:[]).with("STRIPE_WEBHOOK_ENFORCE").and_return(enforce)
    end

    context "when a signing secret is configured" do
      it "processes the event when the signature verifies" do
        stub_env(secret: "whsec_live")
        expect(Stripe::Webhook).to receive(:construct_event).and_return(unhandled_event)
        post :stripe, body: "{}"
        expect(response).to have_http_status(:ok)
      end

      it "accepts a second (test-mode) secret when the first fails" do
        stub_env(secret: "whsec_live", test_secret: "whsec_test")
        allow(Stripe::Webhook).to receive(:construct_event)
          .with(anything, anything, "whsec_live").and_raise(Stripe::SignatureVerificationError.new("bad", "sig"))
        allow(Stripe::Webhook).to receive(:construct_event)
          .with(anything, anything, "whsec_test").and_return(unhandled_event)
        post :stripe, body: "{}"
        expect(response).to have_http_status(:ok)
      end

      context "and the signature does NOT verify" do
        before do
          allow(Stripe::Webhook).to receive(:construct_event)
            .and_raise(Stripe::SignatureVerificationError.new("bad sig", "sig"))
        end

        it "rejects with 400 when enforce is on (forgery blocked)" do
          stub_env(secret: "whsec_live", enforce: "true")
          expect(Stripe::Event).not_to receive(:construct_from)
          post :stripe, body: "{}"
          expect(response).to have_http_status(:bad_request)
        end

        it "still processes (log-only) when enforce is off — the deploy is a no-op" do
          stub_env(secret: "whsec_live", enforce: nil)
          expect(Stripe::Event).to receive(:construct_from).and_return(unhandled_event)
          post :stripe, body: "{}"
          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "when no signing secret is configured yet" do
      it "never enforces and processes unverified (pre-rollout behavior preserved)" do
        stub_env(enforce: "true") # enforce flag is ignored without a secret
        expect(Stripe::Webhook).not_to receive(:construct_event)
        expect(Stripe::Event).to receive(:construct_from).and_return(unhandled_event)
        post :stripe, body: "{}"
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
