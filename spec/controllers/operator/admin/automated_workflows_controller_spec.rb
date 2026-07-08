require "rails_helper"

RSpec.describe Operator::Admin::AutomatedWorkflowsController, type: :controller do
  render_views

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", current_location: location) }
  let(:regular_user) { create(:user, operator: operator, current_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    context "when admin" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "seeds defaults and lists all workflow types" do
        expect {
          get :index
        }.to change { AutomatedWorkflow.count }.by(AutomatedWorkflow::TYPES.size)
        expect(response).to be_successful
        expect(assigns(:workflows).map(&:workflow_type)).to match_array(AutomatedWorkflow::TYPES)
      end

      it "is idempotent (re-seeding does not duplicate)" do
        get :index
        expect { get :index }.not_to change { AutomatedWorkflow.count }
      end
    end

    context "when non-staff user" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "redirects (unauthorized)" do
        get :index
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "PATCH #update" do
    let!(:workflow) do
      AutomatedWorkflow.create!(operator: operator, location: location,
                                workflow_type: "re_engagement",
                                config: { "days_inactive" => 14 },
                                enabled: false)
    end

    before { allow(controller).to receive(:current_user).and_return(admin_user) }

    it "toggles enabled on" do
      patch :update, params: { id: workflow.id, automated_workflow: { enabled: "1" } }
      expect(workflow.reload.enabled).to be true
    end

    it "toggles enabled off" do
      workflow.update!(enabled: true)
      patch :update, params: { id: workflow.id, automated_workflow: { enabled: "0" } }
      expect(workflow.reload.enabled).to be false
    end

    it "persists an updated days_inactive config" do
      patch :update, params: {
        id: workflow.id,
        automated_workflow: { enabled: "1", config: { days_inactive: "30" } },
      }
      expect(workflow.reload.config["days_inactive"]).to eq(30)
      expect(workflow.enabled).to be true
    end

    it "persists days_after for day_passer_followup" do
      dpf = AutomatedWorkflow.create!(operator: operator, location: location,
                                      workflow_type: "day_passer_followup",
                                      config: { "days_after" => 14 }, enabled: false)
      patch :update, params: {
        id: dpf.id,
        automated_workflow: { config: { days_after: "21" } },
      }
      expect(dpf.reload.config["days_after"]).to eq(21)
    end

    it "redirects to the index" do
      patch :update, params: { id: workflow.id, automated_workflow: { enabled: "1" } }
      expect(response).to redirect_to(automated_workflows_path)
    end

    context "when non-staff user" do
      before { allow(controller).to receive(:current_user).and_return(regular_user) }

      it "is blocked by Pundit (no change)" do
        original = workflow.config.dup
        begin
          patch :update, params: { id: workflow.id, automated_workflow: { config: { days_inactive: "99" } } }
        rescue Pundit::NotAuthorizedError
        end
        expect(workflow.reload.config).to eq(original)
      end
    end
  end
end
