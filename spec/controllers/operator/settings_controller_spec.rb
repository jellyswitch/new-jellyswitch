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

    it "attaches an uploaded background image" do
      patch :update_branding, params: {
        operator: { background_image: fixture_file_upload("spec/fixtures/test.jpg", "image/jpeg") }
      }
      expect(response).to redirect_to(settings_branding_path)
      expect(operator.reload.background_image).to be_attached
    end

    it "attaches an uploaded app icon" do
      patch :update_branding, params: {
        operator: { app_icon_image: fixture_file_upload("spec/fixtures/test.jpg", "image/jpeg") }
      }
      expect(response).to redirect_to(settings_branding_path)
      expect(operator.reload.app_icon_image).to be_attached
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

    it "renders background image field" do
      get :branding
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name=\"operator[background_image]\"")
    end

    it "renders the app icon field and prefers the app icon over the logo for the favicon" do
      operator.logo_image.attach(io: File.open(Rails.root.join("spec/fixtures/test.jpg")), filename: "wide-wordmark.jpg", content_type: "image/jpeg")
      operator.app_icon_image.attach(io: File.open(Rails.root.join("spec/fixtures/test.jpg")), filename: "square-icon.jpg", content_type: "image/jpeg")
      get :branding
      expect(response.body).to include("name=\"operator[app_icon_image]\"")
      expect(response.body).to match(/<link rel="icon" href="[^"]*square-icon\.jpg"/)
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
    # Module flags are LOCATION-scoped (PR #504): the form is `form_with model:
    # @location`, so the toggles render as `location[...]`.
    it "renders all 9 module toggles + credits dormant warning" do
      get :modules
      expect(response).to have_http_status(:ok)
      %w[announcements_enabled events_enabled door_integration_enabled rooms_enabled
         offices_enabled bulletin_board_enabled credits_enabled childcare_enabled crm_enabled].each do |attr|
        expect(response.body).to include("location[#{attr}]"), "missing toggle: #{attr}"
      end
      expect(response.body).to include("dormant")
    end
  end

  describe "PATCH #update_modules" do
    # update_modules writes the LOCATION's module flags, not the operator's.
    it "saves module toggles" do
      patch :update_modules, params: {
        location: { announcements_enabled: "0", rooms_enabled: "1" }
      }
      expect(response).to redirect_to(settings_modules_path)
      location.reload
      expect(location.announcements_enabled).to be false
      expect(location.rooms_enabled).to be true
    end

    it "rejects params outside the modules whitelist" do
      original_name = location.name
      patch :update_modules, params: { location: { name: "should not change", rooms_enabled: "1" } }
      location.reload
      expect(location.name).to eq(original_name)
    end
  end

  describe "GET #policies" do
    render_views

    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "renders day pass price input in dollars" do
      operator.update!(day_pass_cost_in_cents: 2599)
      get :policies_tab
      expect(response.body).to include("name=\"operator[day_pass_cost]\"")
      expect(response.body).to include("25.99")
      expect(response.body).to include("step=\"0.01\"")
    end
  end

  describe "PATCH #update_policies" do
    before do
      allow(controller).to receive(:current_operator).and_return(operator)
    end

    it "saves day pass cost converting dollars to cents" do
      patch :update_policies, params: {
        operator: { day_pass_cost: "40.99", refund_fee_percent: "5", cancellation_window_hours: "24", renewal_reminder_days: "7", approval_required: "1", checkin_required: "0" }
      }
      expect(response).to redirect_to(settings_policies_path)
      operator.reload
      expect(operator.day_pass_cost_in_cents).to eq(4099)
      expect(operator.refund_fee_percent).to eq(5)
      expect(operator.cancellation_window_hours).to eq(24)
      expect(operator.renewal_reminder_days).to eq(7)
      expect(operator.approval_required).to be true
      expect(operator.checkin_required).to be false
    end

    it "rejects direct write to day_pass_cost_in_cents" do
      operator.update!(day_pass_cost_in_cents: 2500)
      patch :update_policies, params: { operator: { day_pass_cost_in_cents: "1" } }
      expect(operator.reload.day_pass_cost_in_cents).to eq(2500)
    end
  end

  describe "location switcher pattern" do
    render_views
    let(:other_location) { create(:location, operator: operator, name: "Reno Branch") }

    it "GET #hours_and_address uses params[:location_id] when present" do
      other_location  # force creation
      get :hours_and_address, params: { location_id: other_location.id }
      expect(response.body).to include("Reno Branch")
    end

    it "GET #hours_and_address defaults to current_location when no param" do
      get :hours_and_address
      expect(response.body).to include(location.name)
    end
  end

  describe "GET #hours_and_address" do
    render_views
    it "renders address, hours, and contact fields for the selected location" do
      get :hours_and_address
      expect(response).to have_http_status(:ok)
      %w[name building_address city state zip time_zone
         working_day_start working_day_end open_monday open_saturday
         contact_name contact_email contact_phone building_access_instructions
         latitude longitude].each do |attr|
        expect(response.body).to include("location[#{attr}]"), "missing field: #{attr}"
      end
    end
  end

  describe "PATCH #update_hours_and_address" do
    it "saves address fields" do
      patch :update_hours_and_address, params: {
        location_id: location.id,
        location: {
          name: "Updated Name", building_address: "1 New St", city: "Tahoe",
          state: "CA", zip: "96150", time_zone: "Pacific Time (US & Canada)",
          working_day_start: "08:00", working_day_end: "20:00",
          open_monday: "1", open_saturday: "0",
          contact_name: "Jane", contact_email: "jane@untethered.com", contact_phone: "555-1234"
        }
      }
      expect(response).to redirect_to(settings_hours_and_address_path(location_id: location.id))
      location.reload
      expect(location.name).to eq("Updated Name")
      expect(location.building_address).to eq("1 New St")
      expect(location.working_day_start).to eq("08:00")
    end

    it "rejects params outside the whitelist" do
      original_wifi = location.wifi_name
      patch :update_hours_and_address, params: {
        location_id: location.id,
        location: { wifi_name: "should not change" }
      }
      expect(location.reload.wifi_name).to eq(original_wifi)
    end
  end

  describe "GET #wifi_and_pixels" do
    render_views
    it "renders WiFi fields and existing tracking pixels" do
      location.tracking_pixels.create!(operator: operator, name: "FB Pixel", script: "<script>fbq()</script>")
      get :wifi_and_pixels
      expect(response.body).to include("location[wifi_name]")
      expect(response.body).to include("location[wifi_password]")
      expect(response.body).to include("FB Pixel")
    end
  end

  describe "PATCH #update_wifi_and_pixels" do
    it "saves WiFi credentials" do
      patch :update_wifi_and_pixels, params: {
        location_id: location.id,
        location: { wifi_name: "Untethered-Guest", wifi_password: "letmein" }
      }
      expect(response).to redirect_to(settings_wifi_and_pixels_path(location_id: location.id))
      location.reload
      expect(location.wifi_name).to eq("Untethered-Guest")
      expect(location.wifi_password).to eq("letmein")
    end

    it "adds a new tracking pixel via nested attributes" do
      patch :update_wifi_and_pixels, params: {
        location_id: location.id,
        location: {
          tracking_pixels_attributes: [{ name: "GA", script: "<script>gtag()</script>", operator_id: operator.id }]
        }
      }
      location.reload
      expect(location.tracking_pixels.count).to eq(1)
      expect(location.tracking_pixels.first.name).to eq("GA")
    end

    it "saves the pixel placement (position) so GTM's noscript tag can target the body" do
      patch :update_wifi_and_pixels, params: {
        location_id: location.id,
        location: {
          tracking_pixels_attributes: [{ name: "GTM noscript", script: "<noscript>gtm</noscript>", position: "body", operator_id: operator.id }]
        }
      }
      expect(location.reload.tracking_pixels.first.position).to eq("body")
    end
  end

  describe "GET #payments" do
    render_views

    before { session[:location_id] = location.id }

    context "when location is connected to Stripe" do
      before { location.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx", stripe_publishable_key: "pk_test_abcd1234") }

      it "renders Connected status with last chars of account id" do
        get :payments
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Stripe Connected")
        expect(response.body).to include("1234")  # last 4 of stripe_user_id
        expect(response.body).to include("Reconnect")
      end
    end

    context "when location is not connected" do
      before { location.update!(stripe_user_id: nil, stripe_access_token: nil) }

      it "renders Not Connected status and Connect button" do
        get :payments
        expect(response.body).to include("Stripe Not Connected")
        expect(response.body).to include("Connect Stripe")
      end
    end
  end

  describe "GET #doors" do
    render_views
    it "renders operator KISI key + per-location overrides + import button" do
      operator.update!(kisi_api_key: "operator-key-xyz")
      location.update!(kisi_api_key: nil)
      get :doors
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("operator[kisi_api_key]")
      expect(response.body).to include(location.name)
      expect(response.body).to include("Import doors from KISI")
    end
  end

  describe "PATCH #update_doors" do
    it "saves operator-level KISI key" do
      patch :update_doors, params: { operator: { kisi_api_key: "new-operator-key" } }
      expect(response).to redirect_to(settings_doors_path)
      expect(operator.reload.kisi_api_key).to eq("new-operator-key")
    end

    it "saves per-location override and clears it back to default" do
      patch :update_doors, params: {
        operator: { locations_attributes: [{ id: location.id, kisi_api_key: "loc-override" }] }
      }
      expect(location.reload.kisi_api_key).to eq("loc-override")

      patch :update_doors, params: {
        operator: { locations_attributes: [{ id: location.id, kisi_api_key: "" }] }
      }
      expect(location.reload.kisi_api_key).to be_nil
    end
  end

  describe "POST #import_doors" do
    it "calls Onboarding::GetKisiDoors and redirects" do
      expect(Onboarding::GetKisiDoors).to receive(:call).with(hash_including(location: location)).and_return(double(success?: true))
      post :import_doors, params: { location_id: location.id }
      expect(response).to redirect_to(settings_doors_path(location_id: location.id))
    end
  end

  describe "GET #legacy_redirect" do
    it "redirects to settings_branding_path with 301" do
      get :legacy_redirect
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(settings_branding_path)
    end
  end

  describe "legacy URL routing" do
    it "GET /customization routes to settings#legacy_redirect" do
      expect(get: "/customization").to route_to("operator/settings#legacy_redirect")
    end

    it "GET /operator/operators/:id/edit routes to settings#legacy_redirect" do
      expect(get: "/operator/operators/123/edit").to route_to(
        controller: "operator/settings",
        action: "legacy_redirect",
        id: "123"
      )
    end
  end

  describe "Concierge tab" do
    it "GET #concierge returns 200 and computes the conversion-lift report" do
      get :concierge
      expect(response).to have_http_status(:ok)
      expect(assigns(:report)).to include(:chatters, :non_chatters, :lift)
    end

    describe "embed snippet section" do
      render_views

      it "offers the one-line launcher script as the recommended embed" do
        get :concierge
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("launcher.js")
        expect(response.body).to include("floating chat bubble")
      end
    end

    describe "website widgets tab" do
      render_views

      it "GET #website_widgets renders the consolidated tab with Showcase snippets" do
        get :website_widgets
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Website Widgets")
        expect(response.body).to include("/embed/showcase/#{operator.subdomain}")
      end
    end

    it "PATCH #update_website_widgets toggles the Showcase and saves the shared theme" do
      patch :update_website_widgets, params: { operator: {
        showcase_enabled: "1", embed_accent_override: "112233",
      } }
      expect(response).to redirect_to(settings_website_widgets_path)
      operator.reload
      expect(operator.showcase_enabled).to be true
      expect(operator.embed_accent_override).to eq("#112233")
    end

    it "PATCH #update_concierge saves per-location offer overrides" do
      loc_a = operator.locations.first || create(:location, operator: operator, visible: true)
      loc_b = create(:location, operator: operator, visible: true)

      patch :update_concierge, params: {
        operator: { concierge_offer_text: "Shared offer" },
        locations: {
          loc_a.id.to_s => { concierge_offer_text: "Location A special" },
          loc_b.id.to_s => { concierge_offer_text: "" },
        },
      }

      expect(loc_a.reload.concierge_offer_text).to eq("Location A special")
      expect(loc_b.reload.concierge_offer_text).to be_nil
      expect(loc_a.concierge_offer).to eq("Location A special")
      expect(loc_b.concierge_offer).to eq("Shared offer")
    end

    it "PATCH #update_concierge ignores locations belonging to another operator" do
      foreign = create(:location, operator: create(:operator), concierge_offer_text: "keep me")

      patch :update_concierge, params: {
        operator: { concierge_offer_text: "x" },
        locations: { foreign.id.to_s => { concierge_offer_text: "hijacked" } },
      }

      expect(foreign.reload.concierge_offer_text).to eq("keep me")
    end

    it "PATCH #update_concierge saves the lean per-brand settings" do
      patch :update_concierge, params: { operator: {
        concierge_enabled: "1",
        concierge_assistant_name: "Tahoe Concierge",
        concierge_greeting: "Hey there 👋",
        concierge_offer_text: "First day 50% off",
        embed_accent_override: "ff0000",
      } }

      expect(response).to redirect_to(settings_concierge_path)
      operator.reload
      expect(operator.concierge_enabled).to be true
      expect(operator.concierge_assistant_name).to eq("Tahoe Concierge")
      expect(operator.embed_accent_override).to eq("#ff0000")
    end
  end
end
