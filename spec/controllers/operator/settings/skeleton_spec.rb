require "rails_helper"

RSpec.describe Operator::SettingsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_user).and_return(admin_user)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  it "GET #index redirects to branding" do
    get :index
    expect(response).to redirect_to(branding_settings_path)
  end

  it "GET #branding returns 200" do
    get :branding
    expect(response).to have_http_status(:ok)
  end
end
