require "rails_helper"

RSpec.describe Api::V1::Admin::OfficeWaitlistController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "admin", current_location: location, original_location: location) }
  let(:regular_user) { create(:user, operator: operator, role: "unassigned", current_location: location, original_location: location) }
  let(:office) { create(:office, operator: operator, location: location, name: "Pipkin Suite") }

  def jwt_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  def office_person(name)
    u = create(:user, operator: operator, original_location: location, name: name)
    InterestTag.record(user: u, product: "office", source: "concierge")
    u
  end

  before { request.headers["X-Operator-Subdomain"] = operator.subdomain }

  describe "GET #index" do
    before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

    it "returns the ordered waitlist entries plus the demand stat" do
      p1 = office_person("Pat Prospect")
      p2 = office_person("Riley Prospect")

      get :index
      body = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(body["entries"].map { |e| e["user"]["id"] }).to match_array([p1.id, p2.id])
      expect(body["entries"].first).to include("status", "source", "waiting_days", "customer")
      expect(body["demand"]["waiting_count"]).to eq(2)
      expect(body).to have_key("available_offices")
    end

    it "forbids a non-admin" do
      request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}"
      get :index
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST #offer / #decline" do
    before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

    it "records an offer and returns the new status" do
      person = office_person("Pat Prospect")
      post :offer, params: { user_id: person.id, office_id: office.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("offered")
      expect(person.activities.where(kind: "office_offered")).to exist
    end

    it "records a decline and returns the new status" do
      person = office_person("Pat Prospect")
      post :decline, params: { user_id: person.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("declined")
      expect(person.activities.where(kind: "office_declined")).to exist
    end

    it "forbids a non-admin from working the queue" do
      request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}"
      person = office_person("Pat Prospect")
      post :offer, params: { user_id: person.id }
      expect(response).to have_http_status(:forbidden)
      expect(person.activities.where(kind: "office_offered")).to be_empty
    end
  end
end
