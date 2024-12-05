require "rails_helper"

RSpec.describe OfficeLease, type: :model do
  describe "associations" do
    it { should belong_to(:operator) }
    it { should belong_to(:organization) }
    it { should belong_to(:office) }
    it { should belong_to(:subscription).dependent(:destroy) }
    it { should belong_to(:location) }
    it { should have_one_attached(:lease_agreement) }
  end

  describe "scopes" do
    let!(:active_lease) do
      create(:office_lease,
        start_date: 1.month.ago,
        end_date: 1.month.from_now
      )
    end

    let!(:upcoming_lease) do
      create(:office_lease,
        start_date: 1.month.from_now,
        end_date: 2.months.from_now
      )
    end

    let!(:inactive_lease) do
      create(:office_lease,
        start_date: 2.months.ago,
        end_date: 1.month.ago
      )
    end

    describe ".active" do
      it "returns leases that are currently active" do
        expect(OfficeLease.active).to include(active_lease)
        expect(OfficeLease.active).not_to include(upcoming_lease, inactive_lease)
      end
    end

    describe ".upcoming" do
      it "returns leases that haven't started yet" do
        expect(OfficeLease.upcoming).to include(upcoming_lease)
        expect(OfficeLease.upcoming).not_to include(active_lease, inactive_lease)
      end
    end

    describe ".inactive" do
      it "returns leases that have ended" do
        expect(OfficeLease.inactive).to include(inactive_lease)
        expect(OfficeLease.inactive).not_to include(active_lease, upcoming_lease)
      end
    end
  end

  describe "instance methods" do
    let(:office_lease) { create(:office_lease) }
    let(:subscription) { create(:subscription) }
    let(:organization) { create(:organization, name: "Test Org") }
    let(:office) { create(:office, name: "Office A") }

    describe "#has_lease?" do
      it "returns true when lease agreement is attached" do
        office_lease.lease_agreement.attach(
          io: StringIO.new("dummy file"),
          filename: "lease.pdf",
          content_type: "application/pdf"
        )
        expect(office_lease.has_lease?).to be true
      end

      it "returns false when lease agreement is not attached" do
        expect(office_lease.has_lease?).to be false
      end
    end

    describe "#active?" do
      it "returns true when current time is between start and end dates" do
        office_lease.start_date = 1.month.ago
        office_lease.end_date = 1.month.from_now
        expect(office_lease.active?).to be true
      end

      it "returns false when current time is outside start and end dates" do
        office_lease.start_date = 2.months.ago
        office_lease.end_date = 1.month.ago
        expect(office_lease.active?).to be false
      end
    end

    describe "#subscription_active?" do
      it "delegates to subscription.active?" do
        office_lease.subscription = subscription
        allow(subscription).to receive(:active?).and_return(true)
        expect(office_lease.subscription_active?).to be true
      end
    end

    describe "#eligible_for_renewal?" do
      it "returns true when within renewal window and lease is active" do
        office_lease.start_date = 1.month.ago
        office_lease.end_date = 30.days.from_now
        expect(office_lease.eligible_for_renewal?).to be true
      end

      it "returns false when outside renewal window" do
        office_lease.start_date = 1.month.ago
        office_lease.end_date = 90.days.from_now
        expect(office_lease.eligible_for_renewal?).to be false
      end

      it "returns false when lease is not active" do
        office_lease.start_date = 2.months.ago
        office_lease.end_date = 1.month.ago
        expect(office_lease.eligible_for_renewal?).to be false
      end
    end

    describe "#group_name" do
      it "returns organization name" do
        office_lease.organization = organization
        expect(office_lease.group_name).to eq("Test Org")
      end
    end

    describe "#office_name" do
      it "returns office name" do
        office_lease.office = office
        expect(office_lease.office_name).to eq("Office A")
      end
    end

    describe "#set_end_date!" do
      it "sets subscription end date" do
        office_lease.subscription = subscription
        expect(subscription).to receive(:set_end_date!).with(office_lease.end_date.to_time)
        office_lease.set_end_date!
      end
    end

    describe "#pretty_date" do
      it "returns formatted end date" do
        office_lease.end_date = Date.new(2024, 1, 1)
        expect(office_lease.pretty_date).to eq("01/01/2024")
      end
    end

    describe "#current_period_end" do
      it "returns stripe subscription current period end" do
        stripe_subscription = double("stripe_subscription", current_period_end: 1704067200)
        office_lease.subscription = subscription
        allow(subscription).to receive(:stripe_subscription).and_return(stripe_subscription)
        expect(office_lease.current_period_end).to eq(1704067200)
      end
    end
  end
end