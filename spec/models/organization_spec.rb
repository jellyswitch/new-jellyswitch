require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "associations" do
    it { should have_many(:users).dependent(:nullify) }
    it { should have_many(:office_leases).dependent(:destroy) }
    it { should have_many(:invoices).dependent(:destroy) }
    it { should have_many(:subscriptions).dependent(:destroy) }
    it { should belong_to(:owner).class_name("User").optional }
    it { should belong_to(:billing_contact).class_name("User").optional }
    it { should belong_to(:operator) }
  end

  describe "scopes" do
    let!(:stripe_org) { create(:organization, stripe_customer_id: "cus_123") }
    let!(:out_of_band_org) { create(:organization, out_of_band: true) }
    let!(:ineligible_org) { create(:organization, stripe_customer_id: nil, out_of_band: false) }
    let!(:visible_org) { create(:organization, visible: true) }
    let!(:archived_org) { create(:organization, visible: false) }

    describe ".eligible_for_lease" do
      it "returns organizations with stripe customer or out of band payments" do
        eligible = Organization.eligible_for_lease
        expect(eligible).to include(stripe_org, out_of_band_org)
        expect(eligible).not_to include(ineligible_org)
      end
    end

    describe ".visible" do
      it "returns visible organizations" do
        expect(Organization.visible).to include(visible_org)
        expect(Organization.visible).not_to include(archived_org)
      end
    end

    describe ".archived" do
      it "returns archived organizations" do
        expect(Organization.archived).to include(archived_org)
        expect(Organization.archived).not_to include(visible_org)
      end
    end
  end

  describe "class methods" do
    describe ".options_for_select" do
      let(:location) { create(:location) }
      let!(:org1) { create(:organization, location: location, name: "Org A") }
      let!(:org2) { create(:organization, location: location, name: "Org B") }

      it "returns array of organization names and ids with blank option" do
        options = Organization.options_for_select(location)
        expect(options).to include(["", nil], ["Org A", org1.id], ["Org B", org2.id])
      end
    end
  end

  describe "instance methods" do
    let(:organization) { create(:organization) }
    let(:location) { create(:location) }
    let(:operator) { create(:operator) }

    describe "#has_active_lease?" do
      it "returns true when organization has active lease" do
        create(:office_lease,
          organization: organization,
          start_date: 1.month.ago,
          end_date: 1.month.from_now
        )
        expect(organization.has_active_lease?).to be true
      end

      it "returns false when organization has no active lease" do
        expect(organization.has_active_lease?).to be false
      end
    end

    describe "stripe related methods" do
      let(:stripe_customer_double) { double("Stripe::Customer") }

      before do
        organization.stripe_customer_id = "cus_123"
        allow(organization.operator).to receive(:retrieve_stripe_customer)
          .and_return(stripe_customer_double)
      end

      describe "#stripe_customer" do
        it "returns nil when no stripe_customer_id" do
          organization.stripe_customer_id = nil
          expect(organization.stripe_customer).to be_nil
        end

        it "retrieves stripe customer when stripe_customer_id exists" do
          expect(organization.stripe_customer).to eq(stripe_customer_double)
        end
      end

      describe "#has_billing?" do
        it "returns true when has stripe customer and card" do
          allow(organization).to receive(:has_stripe_customer?).and_return(true)
          allow(organization).to receive(:card_added?).and_return(true)
          expect(organization.has_billing?).to be true
        end

        it "returns false when missing stripe customer or card" do
          allow(organization).to receive(:has_stripe_customer?).and_return(false)
          expect(organization.has_billing?).to be false
        end
      end

      describe "#payment_method" do
        it "returns 'Credit card on file' when has billing" do
          allow(organization).to receive(:has_billing?).and_return(true)
          expect(organization.payment_method).to eq("Credit card on file")
        end

        it "returns 'Via cash or check' when out of band" do
          allow(organization).to receive(:has_billing?).and_return(false)
          organization.out_of_band = true
          expect(organization.payment_method).to eq("Via cash or check")
        end

        it "returns 'None' when no billing and not out of band" do
          allow(organization).to receive(:has_billing?).and_return(false)
          organization.out_of_band = false
          expect(organization.payment_method).to eq("None")
        end
      end
    end

    describe "#has_active_subscriptions?" do
      let(:user) { create(:user, organization: organization) }

      it "returns true when organization has users with active subscriptions" do
        allow(organization).to receive(:active_subscriptions).and_return([double("Subscription")])
        expect(organization.has_active_subscriptions?).to be true
      end

      it "returns false when organization has no active subscriptions" do
        allow(organization).to receive(:active_subscriptions).and_return([])
        expect(organization.has_active_subscriptions?).to be false
      end
    end

    describe "#can_change_billing_contact?" do
      it "returns true when no active subscriptions or leases" do
        allow(organization).to receive(:has_active_subscriptions?).and_return(false)
        allow(organization).to receive(:has_active_lease?).and_return(false)
        expect(organization.can_change_billing_contact?).to be true
      end

      it "returns false when has active subscriptions or leases" do
        allow(organization).to receive(:has_active_subscriptions?).and_return(true)
        expect(organization.can_change_billing_contact?).to be false
      end
    end
  end

  describe "searchkick integration" do
    describe "#search_data" do
      let(:owner) { create(:user, name: "John Doe") }
      let(:organization) do
        create(:organization,
          name: "Test Org",
          owner: owner,
          stripe_customer_id: "cus_123"
        )
      end

      it "returns correct search data hash" do
        expect(organization.search_data).to eq({
          name: "Test Org",
          owner: "John Doe",
          stripe_customer_id: "cus_123"
        })
      end
    end
  end
end