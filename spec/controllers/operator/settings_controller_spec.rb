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
    expect(response).to redirect_to(settings_branding_path)
  end

  it "GET #branding returns 200" do
    get :branding
    expect(response).to have_http_status(:ok)
  end

  describe "PATCH #update_branding" do
    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "updates branding fields" do
      patch :update_branding, params: {
        operator: { snippet: "New snippet", membership_text: "New membership text" }
      }
      expect(response).to redirect_to(settings_branding_path)
      operator.reload
      expect(operator.snippet).to eq("New snippet")
      expect(operator.membership_text).to eq("New membership text")
    end

    it "rejects params outside the branding whitelist" do
      original_kisi = operator.kisi_api_key
      patch :update_branding, params: {
        operator: { kisi_api_key: "should not change" }
      }
      operator.reload
      expect(operator.kisi_api_key).to eq(original_kisi)
    end
  end

  describe "GET #branding (snippet field)" do
    render_views

    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "renders snippet field" do
      operator.update!(snippet: "Test snippet")
      get :branding
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name=\"operator[snippet]\"")
    end
  end
end
