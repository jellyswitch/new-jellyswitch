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

  describe "POST #add_note" do
    context "when authenticated as admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(admin_user)}" }

      it "creates a Note attached to the target user, authored by current_api_user" do
        expect {
          post :add_note, params: { id: target.id, body: "Followed up via mobile" }
        }.to change { Note.where(notable: target).count }.by(1)

        note = Note.where(notable: target).last
        expect(note.author).to eq(admin_user)
        expect(note.operator).to eq(operator)
        expect(note.body.to_plain_text).to include("Followed up via mobile")
      end

      it "writes an Activity row of kind :note via Note#after_create" do
        expect {
          post :add_note, params: { id: target.id, body: "Quick note from phone" }
        }.to change { Activity.where(user: target, kind: "note").count }.by(1)
      end

      it "returns 201 with the new note's id, author, body, created_at" do
        post :add_note, params: { id: target.id, body: "API smoke" }
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["success"]).to be true
        expect(body["note"]["id"]).to be_present
        expect(body["note"]["body"]).to include("API smoke")
        expect(body["note"]["author"]).to eq(admin_user.name)
        expect(body["note"]["created_at"]).to be_present
      end

      it "rejects blank body with 422" do
        post :add_note, params: { id: target.id, body: "" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when not admin" do
      before { request.headers["Authorization"] = "Bearer #{jwt_for(regular_user)}" }

      it "is forbidden and does not create a Note" do
        expect {
          post :add_note, params: { id: target.id, body: "sneaky" }
        }.not_to change { Note.count }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when unauthenticated" do
      it "returns 401" do
        post :add_note, params: { id: target.id, body: "x" }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
