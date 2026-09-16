require "rails_helper"

RSpec.describe "Garmin watch pairing", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, current_location: location, original_location: location) }

  def auth_headers_for(u, extra = {})
    payload = { user_id: u.id, operator_id: u.operator_id, exp: 1.hour.from_now.to_i }.merge(extra)
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => u.operator.subdomain,
    }
  end

  def decode(token)
    JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256").first
  end

  describe "POST /api/v1/me/garmin_pairing_code" do
    it "requires a logged-in phone session" do
      post "/api/v1/me/garmin_pairing_code"
      expect(response).to have_http_status(:unauthorized)
    end

    it "mints a 6-digit code that expires in 10 minutes, stored only as a digest" do
      post "/api/v1/me/garmin_pairing_code", headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["code"]).to match(/\A\d{6}\z/)
      expect(body["expires_in"]).to eq(600)

      user.reload
      expect(user.garmin_pairing_code_digest).to be_present
      expect(user.garmin_pairing_code_digest).not_to include(body["code"])
      expect(user.garmin_pairing_code_expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    end

    it "replaces an earlier code so only the newest one works" do
      post "/api/v1/me/garmin_pairing_code", headers: auth_headers_for(user)
      first = JSON.parse(response.body)["code"]
      post "/api/v1/me/garmin_pairing_code", headers: auth_headers_for(user)
      second = JSON.parse(response.body)["code"]

      post "/api/v1/garmin/pair", params: { code: first }
      expect(response).to have_http_status(:not_found) unless first == second
      post "/api/v1/garmin/pair", params: { code: second }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/garmin/pair" do
    def mint_code
      post "/api/v1/me/garmin_pairing_code", headers: auth_headers_for(user)
      JSON.parse(response.body)["code"]
    end

    it "trades a live code for a long-lived garmin token and the member's context" do
      code = mint_code
      post "/api/v1/garmin/pair", params: { code: code }
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["name"]).to eq(user.name)
      expect(body["subdomain"]).to eq(operator.subdomain)
      expect(body["location"]).to eq(location.name)

      payload = decode(body["token"])
      expect(payload["user_id"]).to eq(user.id)
      expect(payload["client"]).to eq("garmin")
      expect(payload["exp"]).to be_within(60).of(1.year.from_now.to_i)
    end

    it "accepts the code with the spaces the phone shows it with" do
      code = mint_code
      post "/api/v1/garmin/pair", params: { code: "#{code[0, 2]} #{code[2, 2]} #{code[4, 2]}" }
      expect(response).to have_http_status(:ok)
    end

    it "is single-use" do
      code = mint_code
      post "/api/v1/garmin/pair", params: { code: code }
      expect(response).to have_http_status(:ok)
      post "/api/v1/garmin/pair", params: { code: code }
      expect(response).to have_http_status(:not_found)
    end

    it "rejects an unknown or expired code" do
      post "/api/v1/garmin/pair", params: { code: "000000" }
      expect(response).to have_http_status(:not_found)

      code = mint_code
      travel 11.minutes do
        post "/api/v1/garmin/pair", params: { code: code }
        expect(response).to have_http_status(:not_found)
      end
    end

    it "rejects a blank code" do
      post "/api/v1/garmin/pair", params: { code: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "unlocking with the garmin token" do
    let!(:door) { create(:door, operator: operator, location: location, kisi_id: 4242) }

    before do
      allow(Kisi::Client).to receive(:unlock).and_return({ success: true, code: 200, parsed: {}, body: "" })
      # Entitlement is covered elsewhere; this spec is about how the punch is labelled.
      allow_any_instance_of(Api::V1::DoorsController).to receive(:user_can_access_building?).and_return(true)
    end

    it "logs the punch as method garmin" do
      post "/api/v1/doors/#{door.id}/unlock", headers: auth_headers_for(user, client: "garmin")
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to eq(true)
      expect(DoorPunch.where(door: door, user: user).pluck(:method).uniq).to eq(["garmin"])
    end

    it "keeps phone unlocks labelled manual" do
      post "/api/v1/doors/#{door.id}/unlock", headers: auth_headers_for(user)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to eq(true)
      expect(DoorPunch.where(door: door, user: user).pluck(:method).uniq).to eq(["manual"])
    end
  end
end
