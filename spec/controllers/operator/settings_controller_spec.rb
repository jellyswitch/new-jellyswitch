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

  describe "GET #notifications" do
    render_views

    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "renders all 10 notification toggles + Mailchimp + sender_email" do
      get :notifications
      expect(response).to have_http_status(:ok)
      %w[email_enabled reservation_notifications membership_notifications signup_notifications
         day_pass_notifications member_feedback_notifications checkin_notifications
         refund_notifications post_notifications paid_room_reservation_notifications].each do |attr|
        expect(response.body).to include("operator[#{attr}]"), "missing toggle: #{attr}"
      end
      expect(response.body).to include("operator[sender_email]")
      expect(response.body).to include("operator[mailchimp_api_key]")
      expect(response.body).to include("operator[mailchimp_audience_id]")
    end
  end

  describe "PATCH #update_notifications" do
    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "saves notification toggles + Mailchimp fields" do
      patch :update_notifications, params: {
        operator: {
          signup_notifications: "1",
          sender_email: "noreply@untethered.com",
          mailchimp_api_key: "mc-abc",
          mailchimp_audience_id: "aud-1",
        }
      }
      expect(response).to redirect_to(settings_notifications_path)
      operator.reload
      expect(operator.signup_notifications).to be true
      expect(operator.sender_email).to eq("noreply@untethered.com")
      expect(operator.mailchimp_api_key).to eq("mc-abc")
      expect(operator.mailchimp_audience_id).to eq("aud-1")
    end

    it "rejects params outside the notifications whitelist" do
      original_snippet = operator.snippet
      patch :update_notifications, params: { operator: { snippet: "should not change" } }
      operator.reload
      expect(operator.snippet).to eq(original_snippet)
    end
  end

  describe "GET #modules" do
    render_views
    it "renders all 9 module toggles + credits dormant warning" do
      get :modules
      expect(response).to have_http_status(:ok)
      %w[announcements_enabled events_enabled door_integration_enabled rooms_enabled
         offices_enabled bulletin_board_enabled credits_enabled childcare_enabled crm_enabled].each do |attr|
        expect(response.body).to include("operator[#{attr}]"), "missing toggle: #{attr}"
      end
      expect(response.body).to include("dormant")
    end
  end

  describe "PATCH #update_modules" do
    it "saves module toggles" do
      patch :update_modules, params: {
        operator: { announcements_enabled: "0", rooms_enabled: "1" }
      }
      expect(response).to redirect_to(settings_modules_path)
      operator.reload
      expect(operator.announcements_enabled).to be false
      expect(operator.rooms_enabled).to be true
    end

    it "rejects params outside the modules whitelist" do
      original_snippet = operator.snippet
      patch :update_modules, params: { operator: { snippet: "should not change" } }
      operator.reload
      expect(operator.snippet).to eq(original_snippet)
    end
  end
end
