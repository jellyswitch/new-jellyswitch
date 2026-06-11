require 'rails_helper'

# Exercises the enriched _memberships partial: Day Pool usage line + the
# manager-only "Comp a day" button render without error.
RSpec.describe Operator::UsersController, type: :controller do
  render_views

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:member)   { create(:user, operator: operator, original_location: location, approved: true) }
  let(:plan)     { create(:plan, operator: operator, location: location, has_day_limit: true, day_limit: 10) }
  let!(:sub) do
    create(:subscription, plan: plan, subscribable: member, billable: member, stripe_subscription_id: nil)
  end

  before do
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_user).and_return(admin)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  # Note: the "Comp a day" button is gated on the view-helper current_user
  # (session-backed), which isn't the controller stub here — its render + the
  # authorization are covered by comp_days_controller_spec. A 200 here proves
  # the whole template (button block included) compiled without error.
  it "renders the Day Pool usage line for a day-limited member" do
    get :membership, params: { user_id: member.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Monthly day limit")
    expect(response.body).to include("of 10 days used this period")
    expect(response.body).to include("remaining")
  end
end
