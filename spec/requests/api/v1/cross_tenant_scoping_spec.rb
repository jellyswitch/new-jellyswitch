require "rails_helper"

# IDOR / cross-tenant scoping fixes: the JSON API never installs the
# acts_as_scopable tenant default_scope (only the web Operator::BaseController
# does), so bare Model.find(params[:id]) was GLOBAL. These specs prove each
# by-id endpoint now scopes to the caller's operator/location — a foreign id
# returns 404 instead of another tenant's data.
RSpec.describe "API v1 cross-tenant scoping", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:member)   { create(:user, operator: operator, original_location: location) }
  let(:admin)    { create(:user, operator: operator, role: "admin", original_location: location) }

  # A different tenant's resources — the caller should never reach these by id.
  let(:other_operator) { create(:operator) }
  let(:other_location) { create(:location, operator: other_operator) }
  let(:foreign_room)   { create(:room, operator: other_operator, location: other_location) }
  let(:foreign_post)   { create(:post, location: other_location, user: create(:user, operator: other_operator, original_location: other_location)) }
  let(:foreign_event)  { create(:event, location: other_location) }
  let(:foreign_door)   { create(:door, operator: other_operator, location: other_location) }

  def auth_headers_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    {
      "Authorization"        => "Bearer #{JWT.encode(payload, Rails.application.secret_key_base, 'HS256')}",
      "X-Operator-Subdomain" => user.operator.subdomain,
    }
  end

  describe "member-facing endpoints (auth as a member of `operator`)" do
    let(:headers) { auth_headers_for(member) }

    it "does not expose a foreign room's availability/time_slots/pricing" do
      get "/api/v1/rooms/#{foreign_room.id}/availability", headers: headers
      expect(response).to have_http_status(:not_found)
      get "/api/v1/rooms/#{foreign_room.id}/time_slots", headers: headers
      expect(response).to have_http_status(:not_found)
      get "/api/v1/rooms/#{foreign_room.id}/pricing", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "does not expose a foreign event, and cannot RSVP to it" do
      get "/api/v1/events/#{foreign_event.id}", headers: headers
      expect(response).to have_http_status(:not_found)
      post "/api/v1/events/#{foreign_event.id}/rsvp", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "does not expose a foreign post, and cannot reply or react to it" do
      get "/api/v1/posts/#{foreign_post.id}", headers: headers
      expect(response).to have_http_status(:not_found)

      expect {
        post "/api/v1/posts/#{foreign_post.id}/replies", params: { body: "sneaky" }, headers: headers
      }.not_to change(PostReply, :count)
      expect(response).to have_http_status(:not_found)

      post "/api/v1/posts/#{foreign_post.id}/reactions", params: { emoji: "👍" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "cannot book a foreign operator's room" do
      expect {
        post "/api/v1/reservations",
             params: { reservation: { room_id: foreign_room.id, datetime_in: 1.hour.from_now.iso8601, minutes: 60 } },
             headers: headers
      }.not_to change(Reservation, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "still serves the member's OWN post (positive control)" do
      own_post = create(:post, location: location, user: member)
      get "/api/v1/posts/#{own_post.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "admin door endpoints (auth as an admin of `operator`)" do
    let(:headers) { auth_headers_for(admin) }

    it "cannot update, open, or read punches for a foreign operator's door" do
      patch "/api/v1/admin/doors/#{foreign_door.id}",
            params: { name: "Hijacked" }.to_json,
            headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
      expect(foreign_door.reload.name).not_to eq("Hijacked")

      # 404 must be reached BEFORE unlock_door, so no Kisi call happens.
      post "/api/v1/admin/doors/#{foreign_door.id}/open", headers: headers
      expect(response).to have_http_status(:not_found)

      get "/api/v1/admin/doors/#{foreign_door.id}/punches", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "still updates the admin's OWN door (positive control)" do
      own_door = create(:door, operator: operator, location: location)
      patch "/api/v1/admin/doors/#{own_door.id}",
            params: { name: "Renamed" }.to_json,
            headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
      expect(own_door.reload.name).to eq("Renamed")
    end
  end
end
