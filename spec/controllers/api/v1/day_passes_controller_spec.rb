require "rails_helper"

RSpec.describe Api::V1::DayPassesController, type: :controller do
  describe "GET #types" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    it "includes quantity for each type" do
      single = create(:day_pass_type, operator: operator, location: location,
                      name: "Single Pass", amount_in_cents: 1500,
                      quantity: 1, visible: true, available: true)
      npack  = create(:day_pass_type, operator: operator, location: location,
                      name: "5-Pack", amount_in_cents: 6000,
                      quantity: 5, visible: true, available: true)

      get :types
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)

      single_json = body.find { |t| t["id"] == single.id }
      npack_json  = body.find { |t| t["id"] == npack.id }

      expect(single_json).not_to be_nil
      expect(single_json["quantity"]).to eq(1)
      expect(npack_json).not_to be_nil
      expect(npack_json["quantity"]).to eq(5)
    end
  end

  describe "POST #apply_code (fallback to DayPassType)" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let!(:hidden_pass) do
      create(:day_pass_type, operator: operator, location: location,
             code: "CoworkCafe", name: "Cafe Hour Pass", amount_in_cents: 1000,
             visible: false, available: true)
    end

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    it "returns day_pass_type payload when code matches a hidden DayPassType (case-insensitive)" do
      post :apply_code, params: { code: "coworkcafe" }
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["type"]).to eq("day_pass_type")
      expect(body["valid"]).to be true
      expect(body["day_pass_type_id"]).to eq(hidden_pass.id)
      expect(body["day_pass_type_name"]).to eq("Cafe Hour Pass")
      expect(body["amount_in_cents"]).to eq(1000)
    end

    it "returns invalid when neither DiscountCode nor DayPassType matches" do
      post :apply_code, params: { code: "NOPE" }
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body["type"]).to eq("invalid")
      expect(body["valid"]).to be false
    end

    it "prefers DiscountCode when both surfaces have the same code" do
      dc = create(:discount_code, operator: operator, location: location,
                  code: "CoworkCafe", discount_type: "percent_off", discount_value: 50,
                  applies_to: "day_pass", active: true)
      post :apply_code, params: { code: "CoworkCafe" }
      body = JSON.parse(response.body)
      expect(body["type"]).to eq("discount")
      expect(body["code"]).to eq("CoworkCafe")
    end
  end

  describe "POST #create (visible:false bypass via matching access code)" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let!(:hidden_pass) do
      create(:day_pass_type, operator: operator, location: location,
             code: "CoworkCafe", name: "Cafe Hour Pass", amount_in_cents: 1000,
             visible: false, available: true)
    end
    let!(:other_hidden_pass) do
      create(:day_pass_type, operator: operator, location: location,
             code: "SecretMember", name: "Secret Member Pass", amount_in_cents: 5000,
             visible: false, available: true)
    end

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
      # Stub the interactor so we test controller authorization, not the full
      # Stripe charge flow.
      success = double(success?: true, day_pass: nil, message: nil)
      allow(Billing::DayPasses::CreateDayPass).to receive(:call).and_return(success)
      allow(Billing::DayPasses::UpdatePaymentAndCreateDayPass).to receive(:call).and_return(success)
    end

    it "allows purchasing a hidden pass when discount_code matches that pass's access code" do
      post :create, params: { day_pass_type_id: hidden_pass.id, discount_code: "CoworkCafe" }
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["success"]).to be true
    end

    it "rejects a hidden pass when no access code is supplied" do
      post :create, params: { day_pass_type_id: hidden_pass.id }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/not available/i)
    end

    it "rejects a hidden pass when access code does not match" do
      post :create, params: { day_pass_type_id: hidden_pass.id, discount_code: "WrongCode" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/not available/i)
    end

    it "rejects when access code matches a DIFFERENT hidden pass (cross-pass attack)" do
      post :create, params: { day_pass_type_id: hidden_pass.id, discount_code: "SecretMember" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/not available/i)
    end

    it "accepts hidden pass with case-insensitive access code" do
      post :create, params: { day_pass_type_id: hidden_pass.id, discount_code: "coworkcafe" }
      expect(response).to have_http_status(:created)
    end
  end

  # A hidden (visible:false) N-Pack is unlocked by its own access code, which is
  # threaded in as discount_code. The bundle branch must treat that as the access
  # key, not a coupon — otherwise a code-holder can never buy a hidden bundle
  # (the visible-gate requires the code, then the bundle branch rejected it).
  # Parity with the web Operator::DayPassesController#create_bundle guard.
  describe "POST #create — hidden (visible:false) bundle" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let!(:hidden_bundle) do
      create(:day_pass_type, operator: operator, location: location,
             code: "NPACK", name: "Secret 5-Pack", amount_in_cents: 6000,
             quantity: 5, visible: false, available: true)
    end
    let!(:visible_bundle) do
      create(:day_pass_type, operator: operator, location: location,
             name: "Public 5-Pack", amount_in_cents: 6000,
             quantity: 5, visible: true, available: true)
    end

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    def stub_bundle(type)
      result = double(
        success?: true,
        day_pass_bundle: double(id: 1, passes_remaining: type.quantity, day_pass_type: type),
      )
      allow(Billing::DayPassBundles::CreateBundle).to receive(:call).and_return(result)
    end

    it "creates the bundle when its own access code is supplied (not rejected as a coupon)" do
      stub_bundle(hidden_bundle)
      expect(Billing::DayPassBundles::CreateBundle).to receive(:call)
      post :create, params: { day_pass_type_id: hidden_bundle.id, discount_code: "NPACK" }
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["success"]).to be true
    end

    it "rejects a hidden bundle when no access code is supplied (visible-gate)" do
      expect(Billing::DayPassBundles::CreateBundle).not_to receive(:call)
      post :create, params: { day_pass_type_id: hidden_bundle.id }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/not available/i)
    end

    it "rejects a hidden bundle when the access code does not match" do
      expect(Billing::DayPassBundles::CreateBundle).not_to receive(:call)
      post :create, params: { day_pass_type_id: hidden_bundle.id, discount_code: "WrongCode" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/not available/i)
    end

    it "still rejects a real discount code applied to a VISIBLE bundle" do
      create(:discount_code, operator: operator, location: location, code: "SAVE10",
             applies_to: "day_pass", discount_type: "percent_off", discount_value: 10)
      expect(Billing::DayPassBundles::CreateBundle).not_to receive(:call)
      post :create, params: { day_pass_type_id: visible_bundle.id, discount_code: "SAVE10" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/can't be applied/i)
    end
  end

  # A day-pass discount code must pass full validation (scope + expiry +
  # redemption cap), not just the `active` flag — the old dc&.active? check let
  # a member apply a membership-only / expired / maxed code to a day pass.
  describe "POST #create — discount code validation" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let!(:paid_pass) do
      create(:day_pass_type, operator: operator, location: location,
             name: "Single", amount_in_cents: 1500, visible: true, available: true)
    end

    before do
      ActsAsTenant.current_tenant = operator
      allow(controller).to receive(:authenticate_api_v1).and_return(true)
      allow(controller).to receive(:current_api_user).and_return(user)
      allow(controller).to receive(:current_tenant).and_return(operator)
      allow(controller).to receive(:current_location).and_return(location)
    end

    # Stub the interactor and capture what discount_code (if any) it was handed.
    def create_with(code)
      captured = {}
      allow(Billing::DayPasses::CreateDayPass).to receive(:call) do |**kwargs|
        captured = kwargs
        double(success?: true, day_pass: nil)
      end
      post :create, params: { day_pass_type_id: paid_pass.id, discount_code: code }
      captured
    end

    it "applies a valid day-pass discount code" do
      dc = create(:discount_code, operator: operator, location: location, code: "SAVE10",
                  applies_to: "day_pass", discount_type: "percent_off", discount_value: 10)
      kwargs = create_with("SAVE10")
      expect(response).to have_http_status(:created)
      expect(kwargs[:discount_code]).to eq(dc)
    end

    it "does NOT apply a membership-only code to a day pass" do
      create(:discount_code, operator: operator, location: location, code: "MEMBERSONLY",
             applies_to: "membership", discount_type: "percent_off", discount_value: 100)
      kwargs = create_with("MEMBERSONLY")
      expect(response).to have_http_status(:created)
      expect(kwargs[:discount_code]).to be_nil
    end

    it "does NOT apply an expired code" do
      create(:discount_code, operator: operator, location: location, code: "EXPIREDCODE",
             applies_to: "day_pass", discount_type: "percent_off", discount_value: 50, expires_at: 1.day.ago)
      kwargs = create_with("EXPIREDCODE")
      expect(response).to have_http_status(:created)
      expect(kwargs[:discount_code]).to be_nil
    end
  end
end
