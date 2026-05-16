require "rails_helper"

RSpec.describe AutomatedWorkflow, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  describe "TYPES" do
    it "includes the three new automation types" do
      expect(AutomatedWorkflow::TYPES).to include(
        "day_passer_followup",
        "room_reservation_followup",
        "past_member_recovery"
      )
    end
  end

  describe ".seed_defaults_for" do
    before { AutomatedWorkflow.seed_defaults_for(operator, location: location) }

    it "creates a day_passer_followup workflow with days_after: 14" do
      w = AutomatedWorkflow.find_by(operator: operator, location: location, workflow_type: "day_passer_followup")
      expect(w).to be_present
      expect(w.config["days_after"]).to eq(14)
      expect(w.enabled).to be false
    end

    it "creates a room_reservation_followup workflow with days_after: 14" do
      w = AutomatedWorkflow.find_by(operator: operator, location: location, workflow_type: "room_reservation_followup")
      expect(w).to be_present
      expect(w.config["days_after"]).to eq(14)
    end

    it "creates a past_member_recovery workflow with days_after_grace: 30" do
      w = AutomatedWorkflow.find_by(operator: operator, location: location, workflow_type: "past_member_recovery")
      expect(w).to be_present
      expect(w.config["days_after_grace"]).to eq(30)
    end
  end

  describe "#human_name and #description" do
    %w[day_passer_followup room_reservation_followup past_member_recovery].each do |type|
      it "renders human_name and description for #{type}" do
        w = AutomatedWorkflow.new(operator: operator, location: location, workflow_type: type,
                                  config: AutomatedWorkflow::DEFAULT_CONFIGS[type])
        expect(w.human_name).to be_present
        expect(w.description).to be_present
      end
    end
  end
end
