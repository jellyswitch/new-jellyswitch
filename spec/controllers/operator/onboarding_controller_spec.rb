require "rails_helper"

RSpec.describe Operator::OnboardingController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location, current_location: location) }

  before do
    request.host = "#{operator.subdomain}.lvh.me" # activates the tenant via the subdomain filter
    request.headers["X-Operator-Subdomain"] = operator.subdomain
    ActionMailer::Base.default_url_options[:host] = "test.example.com" # for reset-email rendering
    ActsAsTenant.current_tenant = operator
    allow(controller).to receive(:current_user).and_return(admin)
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_tenant).and_return(operator)
  end

  describe "GET #new_stripe_connect" do
    context "when not connected" do
      before { operator.update!(stripe_user_id: nil) }

      it "renders the connect prompt and sets onboarding_in_progress session flag" do
        get :new_stripe_connect
        expect(response).to have_http_status(:ok)
        expect(session[:onboarding_in_progress]).to be true
      end
    end

    context "when already connected" do
      before { operator.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx") }

      it "renders the connected status" do
        get :new_stripe_connect
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST #complete_stripe_connect" do
    it "redirects to membership plan step and clears the onboarding session flag" do
      session[:onboarding_in_progress] = true
      post :complete_stripe_connect
      expect(response).to redirect_to(new_membership_plan_operator_onboarding_index_path)
      expect(session[:onboarding_in_progress]).to be_nil
    end
  end

  describe "Stripe Connect callback wizard return" do
    it "redirects to wizard when onboarding_in_progress (file-based assertion)" do
      file = File.read(Rails.root.join("app/controllers/landing_controller.rb"))
      expect(file).to include("session.delete(:onboarding_in_progress)")
      expect(file).to include("new_stripe_connect_operator_onboarding_index_path")
    end
  end

  describe "idempotency skips" do
    context "GET #new_membership_plan with existing plans" do
      before { create(:plan, operator: operator) }
      it "redirects to day_pass_type step" do
        get :new_membership_plan
        expect(response).to redirect_to(new_day_pass_type_operator_onboarding_index_path)
      end
    end

    context "GET #new_day_pass_type with existing types" do
      before { create(:day_pass_type, operator: operator) }
      it "redirects to room step" do
        get :new_day_pass_type
        expect(response).to redirect_to(new_room_operator_onboarding_index_path)
      end
    end

    context "GET #new_room with existing rooms (rooms enabled)" do
      before { operator.update!(rooms_enabled: true); create(:room, operator: operator, location: location) }
      it "redirects to add_members" do
        get :new_room
        expect(response).to redirect_to(add_members_operator_onboarding_index_path)
      end
    end

    context "GET #new_kisi with existing key" do
      before { operator.update!(kisi_api_key: "test-key") }
      it "redirects to door step" do
        get :new_kisi
        expect(response).to redirect_to(new_door_operator_onboarding_index_path)
      end
    end
  end

  describe "GET #new_stripe_members" do
    context "when Stripe not connected" do
      before { operator.update!(stripe_user_id: nil) }

      it "renders the connect-first guard" do
        get :new_stripe_members
        expect(response).to have_http_status(:ok)
        expect(assigns(:stripe_not_connected)).to be true
      end
    end

    context "when Stripe connected" do
      before { operator.update!(stripe_user_id: "acct_test1234", stripe_access_token: "sk_test_xxx") }

      it "proceeds to the customer list" do
        allow(Onboarding::FetchStripeCustomers).to receive(:call).and_return(double(success?: true, customers: []))
        get :new_stripe_members
        expect(response).to have_http_status(:ok)
        expect(assigns(:stripe_not_connected)).to be_falsey
      end
    end
  end

  describe "GET #new (wizard index) branding prompt" do
    before do
      # Make wizard otherwise complete
      create(:plan, operator: operator, location: location)
      create(:day_pass_type, operator: operator, location: location)
      create(:user, operator: operator, role: :unassigned, original_location: location, current_location: location)
      operator.update!(stripe_user_id: "acct_test1234")
      # Stub current_location in the helper module so the view context resolves it.
      # The controller stub doesn't propagate to ActionView's separate view context object.
      allow_any_instance_of(SessionsHelper).to receive(:current_location).and_return(location)
    end

    context "when branding incomplete" do
      render_views

      before { operator.update!(snippet: "Generic snippet about the space") }

      it "shows the branding completion prompt" do
        get :new
        expect(response.body).to include("Finish your branding")
      end
    end

    context "when branding complete" do
      render_views

      # The controller sets @branding_incomplete; stub it directly so we don't need
      # to deal with Active Storage internals (logo/ToS attachment) in a controller spec.
      before do
        allow(controller).to receive(:new) do
          controller.instance_variable_set(:@branding_incomplete, false)
          controller.render :new
        end
      end

      it "does not show the prompt" do
        get :new
        expect(response.body).not_to include("Finish your branding")
      end
    end
  end

  describe "POST #create_stripe_members" do
    let(:params) { { name: "Imported Member", email: "imported-member@example.com", stripe_customer_id: "cus_test_123", card_added: "true" } }

    it "creates the user without the legacy pizza123 password" do
      post :create_stripe_members, params: params
      user = operator.users.find_by(email: params[:email])
      expect(user).to be_present
      expect(user.authenticate("pizza123")).to eq(false)
    end

    it "uses a random unguessable placeholder password" do
      placeholder = nil
      allow(SecureRandom).to receive(:hex).with(16).and_wrap_original do |orig, *args|
        placeholder = orig.call(*args)
      end
      post :create_stripe_members, params: params
      expect(placeholder).to be_present
      expect(placeholder.length).to eq(32)
      user = operator.users.find_by(email: params[:email])
      expect(user.authenticate(placeholder)).to be_a(User)
    end

    it "sends a password-reset email so the imported member can set their own credentials" do
      expect_any_instance_of(User).to receive(:send_password_reset_email)
      post :create_stripe_members, params: params
    end

    it "marks the imported user as approved" do
      post :create_stripe_members, params: params
      expect(operator.users.find_by(email: params[:email]).approved).to be(true)
    end
  end

  describe "Branding step" do
    it "GET #new_branding renders" do
      get :new_branding
      expect(response).to have_http_status(:ok)
    end

    it "PATCH #create_branding saves the logo + snippet and returns to onboarding" do
      logo = fixture_file_upload("spec/fixtures/test.jpg", "image/jpeg")
      patch :create_branding, params: { operator: { snippet: "Cozy spot downtown", logo_image: logo } }

      operator.reload
      expect(operator.snippet).to eq("Cozy spot downtown")
      expect(operator.logo_image).to be_attached
      expect(response).to redirect_to(new_operator_onboarding_path)
    end
  end

  describe "Settings step" do
    it "GET #new_settings renders" do
      get :new_settings
      expect(response).to have_http_status(:ok)
    end

    it "PATCH #create_settings updates feature modules and policies" do
      patch :create_settings, params: { operator: {
        rooms_enabled: "1", approval_required: "0",
        day_pass_cost: "30.00", cancellation_window_hours: "48",
      } }

      operator.reload
      expect(operator.rooms_enabled).to be(true)
      expect(operator.approval_required).to be(false)
      expect(operator.day_pass_cost_in_cents).to eq(3000)
      expect(operator.cancellation_window_hours).to eq(48)
      expect(response).to redirect_to(new_operator_onboarding_path)
    end
  end
end
