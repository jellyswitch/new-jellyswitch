require "rails_helper"

RSpec.describe Api::V1::DayPassesController, type: :controller do
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
end
