require "rails_helper"

RSpec.describe AutomatedWorkflowsJob, type: :job do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator, visible: true, time_zone: "Pacific Time (US & Canada)") }
  let(:member_user) { create(:user, operator: operator, current_location: location, original_location: location) }

  # Force the job to run outside of quiet hours (9pm–9am local).
  before do
    allow_any_instance_of(AutomatedWorkflowsJob).to receive(:quiet_hours?).and_return(false)
  end

  describe "day_passer_followup" do
    let!(:workflow) do
      AutomatedWorkflow.create!(operator: operator, location: location,
                                workflow_type: "day_passer_followup",
                                config: { "days_after" => 14 }, enabled: true)
    end

    let!(:template) do
      ProductEmailTemplate.create!(operator: operator, location: location,
                                   product_type: "day_pass", email_type: "re_engagement",
                                   subject: "Come back!", enabled: true)
    end

    let!(:day_pass) do
      create(:day_pass, user: member_user, billable: member_user, operator: operator,
                        location: location, day: 14.days.ago.to_date)
    end

    it "records a send via ProductEmailSend for a day-passer who hasn't returned" do
      expect {
        described_class.new.perform
      }.to change { ProductEmailSend.where(email_type: "day_passer_followup_#{day_pass.id}").count }.by(1)
    end

    it "does not record a send if the template is disabled" do
      template.update!(enabled: false)
      expect {
        described_class.new.perform
      }.not_to change { ProductEmailSend.count }
    end

    it "is idempotent (re-running does not double-send)" do
      described_class.new.perform
      expect {
        described_class.new.perform
      }.not_to change { ProductEmailSend.where(email_type: "day_passer_followup_#{day_pass.id}").count }
    end

    it "skips when the user has already returned (additional visit since)" do
      create(:day_pass, user: member_user, billable: member_user, operator: operator,
                        location: location, day: 3.days.ago.to_date)
      expect {
        described_class.new.perform
      }.not_to change { ProductEmailSend.count }
    end
  end

  describe "AutomatedWorkflow handler dispatch" do
    it "routes day_passer_followup to run_day_passer_followup" do
      AutomatedWorkflow.create!(operator: operator, location: location,
                                workflow_type: "day_passer_followup",
                                config: { "days_after" => 14 }, enabled: true)
      job = described_class.new
      expect(job).to receive(:run_day_passer_followup).at_least(:once)
      job.perform
    end

    it "routes room_reservation_followup to run_room_reservation_followup" do
      AutomatedWorkflow.create!(operator: operator, location: location,
                                workflow_type: "room_reservation_followup",
                                config: { "days_after" => 14 }, enabled: true)
      job = described_class.new
      expect(job).to receive(:run_room_reservation_followup).at_least(:once)
      job.perform
    end

    it "routes past_member_recovery to run_past_member_recovery" do
      AutomatedWorkflow.create!(operator: operator, location: location,
                                workflow_type: "past_member_recovery",
                                config: { "days_after_grace" => 30 }, enabled: true)
      job = described_class.new
      expect(job).to receive(:run_past_member_recovery).at_least(:once)
      job.perform
    end
  end
end
