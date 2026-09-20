require 'rails_helper'

RSpec.describe "Admin API: ban member", type: :request do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "admin", original_location: location) }
  let(:member)   { create(:user, operator: operator, original_location: location, approved: true) }
  let(:plan)     { create(:plan, operator: operator, location: location) }

  def auth_headers_for(user)
    payload = { user_id: user.id, operator_id: user.operator_id, exp: 1.hour.from_now.to_i }
    {
      "Authorization"        => "Bearer #{JWT.encode(payload, Rails.application.secret_key_base, 'HS256')}",
      "X-Operator-Subdomain" => user.operator.subdomain,
    }
  end

  it "bans and lifts the ban" do
    post "/api/v1/admin/members/#{member.id}/ban", headers: auth_headers_for(admin)
    expect(response).to have_http_status(:ok)
    expect(member.reload).to be_banned
    expect(member.approved).to be false
    expect(member.marketing_suppressed).to be true

    get "/api/v1/admin/members/#{member.id}", headers: auth_headers_for(admin)
    body = JSON.parse(response.body)
    expect(body["banned"]).to be true
    expect(body["banned_by_name"]).to eq(admin.name)

    post "/api/v1/admin/members/#{member.id}/lift_ban", headers: auth_headers_for(admin)
    expect(response).to have_http_status(:ok)
    expect(member.reload).not_to be_banned
    expect(member.approved).to be true
  end

  it "unarchive refuses a banned member" do
    member.ban!(by: admin)
    post "/api/v1/admin/members/#{member.id}/unarchive", headers: auth_headers_for(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(member.reload).to be_banned
  end

  it "a banned member cannot buy a membership from the app" do
    member.ban!(by: admin)
    post "/api/v1/subscriptions", params: { plan_id: plan.id }, headers: auth_headers_for(member)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to eq(User::BANNED_MESSAGE)
    expect(member.subscriptions.count).to eq(0)
  end

  it "login and /me report the banned flag" do
    member.ban!(by: admin)
    get "/api/v1/me", headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["banned"]).to be true
  end
end
