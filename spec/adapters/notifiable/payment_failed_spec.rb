require 'rails_helper'

RSpec.describe Notifiable::PaymentFailed do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, current_location: location) }
  let(:invoice) do
    create(:invoice, operator: operator, location: location, billable: user,
                     amount_due: 12_550, status: "open")
  end

  subject { described_class.new(invoice) }

  describe "#message" do
    it "includes the dollar amount and asks for a card update" do
      expect(subject.send(:message)).to eq("Your $125.50 payment failed — please update your card.")
    end

    context "when the invoice bills an Organization" do
      let(:organization) { create(:organization, operator: operator, owner: user) }
      let(:invoice) do
        create(:invoice, operator: operator, location: location, billable: organization,
                         amount_due: 5000, status: "open")
      end

      it "words the ask org-side — the owner's personal card isn't the failing one" do
        expect(subject.send(:message))
          .to eq("Your organization's $50.00 payment failed — please update its payment method.")
      end
    end
  end

  describe "#recipients" do
    it "returns the billable user" do
      expect(subject.send(:recipients)).to eq([user])
    end

    context "when the invoice bills an Organization" do
      let(:org_owner) { create(:user, operator: operator, current_location: location) }
      let(:organization) { create(:organization, operator: operator, owner: org_owner) }
      let(:invoice) do
        create(:invoice, operator: operator, location: location, billable: organization,
                         amount_due: 5000, status: "open")
      end

      it "returns the organization's owner" do
        expect(subject.send(:recipients)).to eq([org_owner])
      end
    end

    context "when an Organization has no owner" do
      let(:organization) { create(:organization, operator: operator, owner: nil) }
      let(:invoice) do
        create(:invoice, operator: operator, location: location, billable: organization,
                         amount_due: 5000, status: "open")
      end

      it "returns an empty list rather than [nil]" do
        expect(subject.send(:recipients)).to eq([])
      end
    end
  end

  describe "#deep_link_data" do
    it "routes as payment_failed to the invoice" do
      expect(subject.send(:deep_link_data)).to eq({
        type: "payment_failed",
        resource_id: invoice.id,
        path: "/billing"
      })
    end

    context "when the invoice bills an Organization" do
      let(:organization) { create(:organization, operator: operator, owner: user) }
      let(:invoice) do
        create(:invoice, operator: operator, location: location, billable: organization,
                         amount_due: 5000, status: "open")
      end

      it "uses org_payment_failed (no mobile target) so the tap can't mis-route to the personal card screen" do
        expect(subject.send(:deep_link_data)[:type]).to eq("org_payment_failed")
      end
    end
  end

  describe "#should_send_notification?" do
    it "returns true while the invoice is still open" do
      expect(subject.send(:should_send_notification?)).to be true
    end

    it "returns false once the invoice is paid (no stale 'payment failed' push)" do
      invoice.update!(status: "paid")
      expect(subject.send(:should_send_notification?)).to be false
    end
  end

  describe "#create_feed_item" do
    it "does not create a feed item (the webhook already posts the admin one)" do
      expect { subject.send(:create_feed_item) }.not_to change(FeedItem, :count)
    end
  end

  describe "factory registration" do
    it "resolves via NotifiableFactory with an explicit type" do
      expect(NotifiableFactory.for(invoice, "PaymentFailed")).to be_a(described_class)
    end
  end

  describe "#notify (the entry point SendNotificationsJob actually calls)" do
    it "runs end-to-end without raising and without creating a feed item" do
      # No APNs env / FCM key in test, so send paths are logged no-ops; this
      # pins that validate! passes (non-blank message, resolvable recipients).
      expect { subject.notify }.not_to change(FeedItem, :count)
    end

    it "pushes to the recipient's device while the invoice is open" do
      user.update!(ios_token: "tok_TEST")
      allow(subject).to receive(:apns_configured?).and_return(true)
      allow(operator).to receive(:bundle_id).and_return("com.test.app")
      fake = instance_double(IosNotification, send!: double(ok?: true))
      expect(IosNotification).to receive(:new)
        .with(hash_including(user: user, message: subject.send(:message)))
        .and_return(fake)

      subject.notify
    end

    it "does not push once the invoice is settled" do
      invoice.update!(status: "paid")
      expect(IosNotification).not_to receive(:new)
      subject.notify
    end
  end
end
