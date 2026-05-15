require "rails_helper"

RSpec.describe Invoice, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location) }
  let(:organization) { create(:organization) }

  describe "associations" do
    it { should belong_to(:billable) }
    it { should have_many(:checkins) }
    it { should have_many(:refunds) }
  end

  describe "scopes" do
    let!(:recent_invoice) { create(:invoice, date: 15.days.ago) }
    let!(:old_invoice) { create(:invoice, date: 45.days.ago) }
    let!(:open_invoice) { create(:invoice, status: "open") }
    let!(:paid_invoice) { create(:invoice, status: "paid") }
    let!(:due_invoice) { create(:invoice, status: "open", due_date: 1.day.from_now) }
    let!(:delinquent_invoice) { create(:invoice, status: "open", due_date: 1.day.ago) }
    let!(:group_invoice) { create(:invoice, billable_type: "Organization") }

    it "recent scope returns invoices from last 30 days" do
      expect(Invoice.recent).to include(recent_invoice)
      expect(Invoice.recent).not_to include(old_invoice)
    end

    it "open scope returns open invoices" do
      expect(Invoice.open).to include(open_invoice)
      expect(Invoice.open).not_to include(paid_invoice)
    end

    it "paid scope returns paid invoices" do
      expect(Invoice.paid).to include(paid_invoice)
      expect(Invoice.paid).not_to include(open_invoice)
    end

    it "due scope returns open invoices not past due date" do
      expect(Invoice.due).to include(due_invoice)
      expect(Invoice.due).not_to include(delinquent_invoice)
    end

    it "delinquent scope returns open invoices past due date" do
      expect(Invoice.delinquent).to include(delinquent_invoice)
      expect(Invoice.delinquent).not_to include(due_invoice)
    end

    it "groups scope returns organization invoices" do
      expect(Invoice.groups).to include(group_invoice)
    end
  end

  describe "instance methods" do
    let(:invoice) { create(:invoice) }

    describe "status methods" do
      (Invoice::STATUSES - ['refunded']).each do |status|
        it "#{status}? returns true when status is #{status}" do
          invoice.status = status
          expect(invoice.send("#{status}?")).to be true
        end
      end
    end

    describe "#voidable?" do
      it "returns true for open status" do
        invoice.status = "open"
        expect(invoice.voidable?).to be true
      end

      it "returns true for uncollectible status" do
        invoice.status = "uncollectible"
        expect(invoice.voidable?).to be true
      end

      it "returns false for paid status" do
        invoice.status = "paid"
        expect(invoice.voidable?).to be false
      end
    end

    describe "#pretty_due_date" do
      it "returns formatted due date" do
        invoice.due_date = Time.zone.local(2024, 1, 1)
        expect(invoice.pretty_due_date).to eq("01/01/2024")
      end

      it "returns nil when due date is nil" do
        invoice.due_date = nil
        expect(invoice.pretty_due_date).to be_nil
      end
    end

    describe "#pretty_date" do
      it "returns formatted date" do
        invoice.date = Time.zone.local(2024, 1, 1, 14, 30)
        expect(invoice.pretty_date).to eq("01/01/2024 2:30pm")
      end

      it "returns nil when date is nil" do
        invoice.date = nil
        expect(invoice.pretty_date).to be_nil
      end
    end
  end

  describe "Stripe integration" do
    let(:invoice) { create(:invoice, stripe_invoice_id: "stripe_123") }
    let(:stripe_invoice_double) { double("Stripe::Invoice") }

    before do
      allow(Stripe::Invoice).to receive(:retrieve).and_return(stripe_invoice_double)
    end

    describe "#stripe_invoice" do
      it "retrieves stripe invoice when stripe_invoice_id is present" do
        expect(invoice.stripe_invoice).to eq(stripe_invoice_double)
      end

      it "returns nil when stripe_invoice_id is not present" do
        invoice.stripe_invoice_id = nil
        expect(invoice.stripe_invoice).to be_nil
      end
    end

    describe "#payment_method" do
      context "when stripe invoice exists" do
        it "returns Credit Card for automatic billing" do
          allow(stripe_invoice_double).to receive(:billing).and_return("charge_automatically")
          expect(invoice.payment_method).to eq("Credit Card")
        end

        it "returns Out of band for manual billing" do
          allow(stripe_invoice_double).to receive(:billing).and_return("send_invoice")
          expect(invoice.payment_method).to eq("Out of band")
        end
      end

      it "returns nil when stripe invoice does not exist" do
        invoice.stripe_invoice_id = nil
        expect(invoice.payment_method).to be_nil
      end
    end
  end

  describe "activity logging" do
    let(:user) { create(:user) }
    let(:logged_operator) { create(:operator) }

    it "logs :payment_succeeded when status flips to 'paid'" do
      invoice = create(:invoice, billable: user, operator: logged_operator, status: "open")

      expect { invoice.update!(status: "paid") }.to change(Activity, :count).by(1)
      activity = Activity.last
      expect(activity.kind).to eq("payment_succeeded")
      expect(activity.user).to eq(user)
      expect(activity.subject).to eq(invoice)
    end

    it "logs :payment_failed when status flips to 'uncollectible'" do
      invoice = create(:invoice, billable: user, operator: logged_operator, status: "open")

      expect { invoice.update!(status: "uncollectible") }.to change(Activity, :count).by(1)
      expect(Activity.last.kind).to eq("payment_failed")
    end

    it "does not log on unrelated status transitions (e.g. void)" do
      invoice = create(:invoice, billable: user, operator: logged_operator, status: "open")
      expect { invoice.update!(status: "void") }.not_to change(Activity, :count)
    end

    it "does not log when billable is not a User (e.g. Organization)" do
      invoice = create(:invoice, status: "open") # factory default is Organization billable
      expect { invoice.update!(status: "paid") }.not_to change(Activity, :count)
    end

    it "denormalizes amount, status, and invoice number into payload" do
      invoice = create(:invoice, billable: user, operator: logged_operator, status: "open", amount_due: 5000, amount_paid: 0)
      invoice.update!(status: "paid", amount_paid: 5000)

      payload = Activity.last.payload
      expect(payload["amount_due"]).to eq(5000)
      expect(payload["amount_paid"]).to eq(5000)
      expect(payload["status"]).to eq("paid")
      expect(payload["number"]).to eq(invoice.number)
    end
  end
end