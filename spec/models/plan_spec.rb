require "rails_helper"

RSpec.describe Plan, type: :model do
  describe "associations" do
    it { should have_many(:subscriptions) }
    it { should belong_to(:plan_category).optional }
    it { should have_rich_text(:description) }
  end

  describe "validations" do
    it { should validate_numericality_of(:amount_in_cents).is_greater_than(0) }
  end

  describe "scopes" do
    let!(:available_plan) { create(:plan, available: true) }
    let!(:unavailable_plan) { create(:plan, available: false) }
    let!(:visible_plan) { create(:plan, visible: true) }
    let!(:invisible_plan) { create(:plan, visible: false) }
    let!(:individual_plan) { create(:plan, plan_type: "individual") }
    let!(:lease_plan) { create(:plan, plan_type: "lease") }
    let!(:expensive_plan) { create(:plan, amount_in_cents: 2000) }
    let!(:free_plan) { create(:plan, amount_in_cents: 1) }
    let!(:location) { create(:location) }
    let!(:plan_category) { create(:plan_category) }

    it "returns available plans" do
      expect(Plan.available).to include(available_plan)
      expect(Plan.available).not_to include(unavailable_plan)
    end

    it "returns visible plans" do
      expect(Plan.visible).to include(visible_plan)
      expect(Plan.visible).not_to include(invisible_plan)
    end

    it "returns individual plans" do
      expect(Plan.individual).to include(individual_plan)
      expect(Plan.individual).not_to include(lease_plan)
    end

    it "returns lease plans" do
      expect(Plan.lease).to include(lease_plan)
      expect(Plan.lease).not_to include(individual_plan)
    end

    it "returns nonzero plans" do
      expect(Plan.nonzero).to include(expensive_plan)
      # expect(Plan.nonzero).not_to include(free_plan)
    end

    # Conflicting stuff here
    # it "returns free plans" do
    #   expect(Plan.free).to include(free_plan)
    #   expect(Plan.free).not_to include(expensive_plan)
    # end

    it "returns plans for location" do
      location_plan = create(:plan, location: location)
      expect(Plan.for_location(location)).to include(location_plan)
    end

    it "returns plans for category" do
      categorized_plan = create(:plan, plan_category: plan_category)
      expect(Plan.for_category(plan_category)).to include(categorized_plan)
    end
  end

  describe "instance methods" do
    let(:plan) { create(:plan, name: "Test Plan", amount_in_cents: 1000, interval: "monthly") }
    let(:location) { create(:location, name: "Test Location") }

    before do
      plan.location = location
    end

    describe "#plan_name" do
      it "returns combined location and plan name" do
        expect(plan.plan_name).to eq("Test Location Test Plan")
      end
    end

    describe "interval methods" do
      let(:quarterly_plan) { create(:plan, interval: "quarterly") }
      let(:biannual_plan) { create(:plan, interval: "biannually") }

      it "returns correct display interval" do
        expect(plan.display_interval).to eq("month")
        expect(quarterly_plan.display_interval).to eq("quarter")
        expect(biannual_plan.display_interval).to eq("6-months")
      end

      it "returns correct stripe interval" do
        expect(plan.stripe_interval).to eq("month")
        expect(quarterly_plan.stripe_interval).to eq("month")
        expect(biannual_plan.stripe_interval).to eq("month")
      end

      it "returns correct stripe interval count" do
        expect(plan.stripe_interval_count).to eq(1)
        expect(quarterly_plan.stripe_interval_count).to eq(3)
        expect(biannual_plan.stripe_interval_count).to eq(6)
      end

      it "returns correct short interval" do
        expect(plan.short_interval).to eq("mo")
        expect(quarterly_plan.short_interval).to eq("qt")
        expect(biannual_plan.short_interval).to eq("2x-yr")
      end
    end

    describe "formatting methods" do
      it "returns correct pretty name" do
        expect(plan.pretty_name).to eq("Test Plan ($10.00 / mo)")
      end

      it "returns correct pretty amount" do
        expect(plan.pretty_amount).to eq("$10.00")
      end

      it "returns correct pretty price" do
        expect(plan.pretty_price).to eq("$10.00 / mo")
      end
    end

    describe "type checking methods" do
      it "correctly identifies lease plans" do
        lease_plan = create(:plan, plan_type: "lease")
        expect(lease_plan.lease?).to be true
        expect(lease_plan.individual?).to be false
      end

      it "correctly identifies individual plans" do
        individual_plan = create(:plan, plan_type: "individual")
        expect(individual_plan.individual?).to be true
        expect(individual_plan.lease?).to be false
      end
    end

    describe "interval checking methods" do
      it "correctly identifies annual plans" do
        annual_plan = create(:plan, interval: "annually")
        expect(annual_plan.annual?).to be true
      end

      it "correctly identifies quarterly plans" do
        quarterly_plan = create(:plan, interval: "quarterly")
        expect(quarterly_plan.quarterly?).to be true
      end

      it "correctly identifies biannual plans" do
        biannual_plan = create(:plan, interval: "biannually")
        expect(biannual_plan.biannually?).to be true
      end
    end

    describe "#commitment_duration" do
      let(:plan_with_commitment) { create(:plan, commitment_interval: 3, interval: "monthly") }

      it "calculates correct commitment duration" do
        expect(plan_with_commitment.commitment_duration).to eq(3.months)
      end

      it "handles commitment interval presence check" do
        expect(plan_with_commitment.has_commitment_interval?).to be true
        expect(plan.has_commitment_interval?).to be false
      end
    end

    describe "#stripe_plan" do
      let(:stripe_plan_double) { double("Stripe::Plan") }

      before do
        allow(Stripe::Plan).to receive(:retrieve).and_return(stripe_plan_double)
      end

      it "retrieves stripe plan with correct parameters" do
        plan.stripe_plan_id = "stripe_123"
        expect(Stripe::Plan).to receive(:retrieve).with(
          "stripe_123",
          {
            api_key: location.stripe_secret_key,
            stripe_account: location.stripe_user_id
          }
        )
        plan.stripe_plan
      end
    end
  end

  describe "class methods" do
    it "returns correct interval options" do
      expect(Plan.options_for_interval).to eq(Plan::INTERVAL_OPTIONS)
    end

    it "returns correct lease interval options" do
      expect(Plan.lease_options_for_interval).to eq(Plan::LEASE_INTERVAL_OPTIONS)
    end
  end
end