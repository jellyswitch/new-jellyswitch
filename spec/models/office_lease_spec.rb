require "rails_helper"

RSpec.describe OfficeLease, type: :model do
  describe "eligible_for_renewal?" do
    context "when the lease is active and within the renewal window" do
      it "returns true" do
        lease = create(:office_lease, start_date: Date.today, end_date: Date.today + 59.days)
        expect(lease.eligible_for_renewal?).to be true
      end
    end

    context "when the lease is not active" do
      it "returns false" do
        lease = create(:office_lease, start_date: Date.today - 1.year, end_date: Date.today - 1.day)
        expect(lease.eligible_for_renewal?).to be false
      end
    end

    context "when the lease is active but not within the renewal window" do
      it "returns false" do
        lease = create(:office_lease, start_date: Date.today - 1.year, end_date: Date.today + 2.months)
        expect(lease.eligible_for_renewal?).to be false
      end
    end
  end

  describe "scopes" do
    let!(:active_lease_1) { create(:office_lease, start_date: 1.month.ago, end_date: 11.months.from_now) }
    let!(:active_lease_2) { create(:office_lease, start_date: 2.months.ago, end_date: 10.months.from_now) }
    let!(:upcoming_lease_1) { create(:office_lease, start_date: 1.month.from_now, end_date: 13.months.from_now) }
    let!(:upcoming_lease_2) { create(:office_lease, start_date: 2.months.from_now, end_date: 14.months.from_now) }
    let!(:inactive_lease_1) { create(:office_lease, start_date: 2.years.ago, end_date: 1.year.ago) }
    let!(:inactive_lease_2) { create(:office_lease, start_date: 3.years.ago, end_date: 2.years.ago) }

    describe ".active" do
      it "returns active leases" do
        expect(OfficeLease.active).to contain_exactly(active_lease_1, active_lease_2)
      end
    end

    describe ".upcoming" do
      it "returns upcoming leases" do
        expect(OfficeLease.upcoming).to contain_exactly(upcoming_lease_1, upcoming_lease_2)
      end
    end

    describe ".inactive" do
      it "returns inactive leases" do
        expect(OfficeLease.inactive).to contain_exactly(inactive_lease_1, inactive_lease_2)
      end
    end
  end
end
