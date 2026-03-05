require "rails_helper"

RSpec.describe Navigation::Member do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, door_integration_enabled: true) }
  let!(:door) { create(:door, operator: operator, location: location) }

  describe "#paths" do
    context "approved member with active subscription" do
      let(:user) { create(:user, operator: operator, original_location: location, approved: true) }
      let(:nav) { described_class.new(operator, location, user) }

      before do
        plan = create(:plan, operator: operator, location: location)
        create(:subscription, subscribable: user, billable: user, plan: plan,
               start_date: 1.month.ago, pending: false)
      end

      it "includes Building Access when doors exist and door_integration is enabled" do
        titles = nav.paths.map { |item| item[:title] }
        expect(titles).to include("Building Access")
      end
    end

    context "approved member without active subscription or day pass" do
      let(:user) { create(:user, operator: operator, original_location: location, approved: true) }
      let(:nav) { described_class.new(operator, location, user) }

      it "does not include Building Access" do
        titles = nav.paths.map { |item| item[:title] }
        expect(titles).not_to include("Building Access")
      end
    end

    context "when door_integration_enabled is false" do
      let(:user) { create(:user, operator: operator, original_location: location, approved: true) }

      before do
        plan = create(:plan, operator: operator, location: location)
        create(:subscription, subscribable: user, billable: user, plan: plan,
               start_date: 1.month.ago, pending: false)
        location.update!(door_integration_enabled: false)
      end

      it "does not include Building Access" do
        nav = described_class.new(operator, location, user)
        titles = nav.paths.map { |item| item[:title] }
        expect(titles).not_to include("Building Access")
      end
    end

    context "when no doors exist" do
      let(:user) { create(:user, operator: operator, original_location: location, approved: true) }

      before do
        plan = create(:plan, operator: operator, location: location)
        create(:subscription, subscribable: user, billable: user, plan: plan,
               start_date: 1.month.ago, pending: false)
        Door.where(location: location).destroy_all
      end

      it "does not include Building Access" do
        nav = described_class.new(operator, location, user)
        titles = nav.paths.map { |item| item[:title] }
        expect(titles).not_to include("Building Access")
      end
    end
  end
end
