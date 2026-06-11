require "rails_helper"
RSpec.describe Operator::OfficeLeasesController, type: :controller do
  render_views
  let!(:office_lease) { create(:office_lease, deposit_amount_in_cents: 25000, start_date: Date.today - 1.month, end_date: Date.today + 1.month) }
  let!(:admin) { create(:user, role: User::ADMIN, managed_locations: [office_lease.location]) }
  before do
    allow(controller).to receive(:current_user).and_return(admin)
    allow_any_instance_of(OfficeLease).to receive(:subscription_active?).and_return(true)
  end
  it "shows the deposit not-invoiced warning + actions" do
    get :show, params: { id: office_lease.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Not yet invoiced")
    expect(response.body).to include("Generate deposit invoice")
    expect(response.body).to include("Mark as already invoiced")
  end
end
