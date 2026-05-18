require "rails_helper"

RSpec.describe Api::V1::Admin::MembersController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "admin", current_location: location) }
  let(:regular_user) { create(:user, operator: operator, role: "unassigned", current_location: location) }
  let!(:target) { create(:user, operator: operator, current_location: location, name: "Tour Taker") }

  def jwt_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    JWT.encode(payload, Rails.application.secret_key_base, "HS256")
  end

  before do
    request.headers["X-Operator-Subdomain"] = operator.subdomain
  end

  describe "POST #log_tour" do
    context "when authenticated as admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

      it "creates a tour Activity with notes + logged_by_user_id payload" do
        expect {
          post :log_tour, params: { id: target.id, notes: "Walk-in from API" }
        }.to change { Activity.where(user: target, kind: "tour").count }.by(1)

        activity = Activity.where(user: target, kind: "tour").last
        expect(activity.operator).to eq(operator)
        expect(activity.payload["notes"]).to eq("Walk-in from API")
        expect(activity.payload["logged_by_user_id"]).to eq(admin_user.id)
      end

      it "accepts blank notes (optional)" do
        expect {
          post :log_tour, params: { id: target.id, notes: "" }
        }.to change { Activity.where(user: target, kind: "tour").count }.by(1)
      end

      it "returns 201 with activity id + occurred_at" do
        post :log_tour, params: { id: target.id, notes: "Quick walkthrough" }
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["success"]).to be true
        expect(body["activity"]["id"]).to be_present
        expect(body["activity"]["occurred_at"]).to be_present
      end

    end

    context "when not admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}" }

      it "is forbidden and does not create an Activity" do
        expect {
          post :log_tour, params: { id: target.id, notes: "sneaky" }
        }.not_to change { Activity.where(user: target, kind: "tour").count }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "returns 401" do
        post :log_tour, params: { id: target.id, notes: "x" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
