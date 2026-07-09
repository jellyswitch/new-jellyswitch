# == Schema Information
#
# Table name: office_leases
#
#  id                           :bigint(8)        not null, primary key
#  always_allow_building_access :boolean          default(TRUE), not null
#  auto_renew                   :boolean          default(FALSE), not null
#  deposit_amount_in_cents      :integer          default(0), not null
#  end_date                     :date             not null
#  escalation_type              :string
#  escalation_value             :decimal(10, 2)
#  initial_invoice_date         :date
#  renewal_notice_days          :integer          default(60), not null
#  start_date                   :date             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  cpi_index_series_id          :string
#  location_id                  :bigint(8)
#  office_id                    :bigint(8)
#  operator_id                  :bigint(8)
#  organization_id              :bigint(8)
#  subscription_id              :bigint(8)
#  user_id                      :bigint(8)
#
# Indexes
#
#  index_office_leases_on_location_id      (location_id)
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_subscription_id  (subscription_id)
#  index_office_leases_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id) ON DELETE => nullify
#  fk_rails_...  (office_id => offices.id) ON DELETE => nullify
#  fk_rails_...  (operator_id => operators.id) ON DELETE => nullify
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => nullify
#  fk_rails_...  (subscription_id => subscriptions.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe OfficeLease, type: :model do
  describe "associations" do
    it { should belong_to(:operator) }
    it { should belong_to(:organization).optional }
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

    describe "#termination_options" do
      it "offers full options (cycle + now) when the subscription is active" do
        allow(office_lease).to receive(:subscription_active?).and_return(true)
        expect(office_lease.termination_options).to eq(:full)
      end

      it "offers immediate-only for a zombie lease: running but subscription inactive" do
        allow(office_lease).to receive(:subscription_active?).and_return(false)
        office_lease.start_date = Date.today - 1.month
        office_lease.end_date   = Date.today + 1.month
        expect(office_lease.termination_options).to eq(:now)
      end

      it "offers none when the lease is no longer active" do
        allow(office_lease).to receive(:subscription_active?).and_return(false)
        office_lease.start_date = Date.today - 2.months
        office_lease.end_date   = Date.today - 1.month
        expect(office_lease.termination_options).to eq(:none)
      end
    end
  end

  describe "culling office interest tags on creation (fairness-queue auto-cull)" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:office)   { create(:office, operator: operator, location: location) }

    it "removes an individual leaseholder's office interest tag" do
      user = create(:user, operator: operator, original_location: location)
      InterestTag.record(user: user, product: "office", source: "concierge")

      create(:office_lease, organization: nil, user: user, operator: operator, location: location, office: office)

      expect(user.interest_tags.for_product("office")).to be_empty
    end

    it "removes the office tag of every member when an organization leases" do
      org = create(:organization, operator: operator)
      m1 = create(:user, operator: operator, organization: org, original_location: location)
      m2 = create(:user, operator: operator, organization: org, original_location: location)
      InterestTag.record(user: m1, product: "office", source: "concierge")
      InterestTag.record(user: m2, product: "office", source: "staff", added_by: m1)

      create(:office_lease, organization: org, user: nil, operator: operator, location: location, office: office)

      expect(m1.interest_tags.for_product("office")).to be_empty
      expect(m2.interest_tags.for_product("office")).to be_empty
    end

    it "leaves interest in other products untouched" do
      user = create(:user, operator: operator, original_location: location)
      InterestTag.record(user: user, product: "membership", source: "concierge")

      create(:office_lease, organization: nil, user: user, operator: operator, location: location, office: office)

      expect(user.interest_tags.for_product("membership")).to be_present
    end
  end
end
