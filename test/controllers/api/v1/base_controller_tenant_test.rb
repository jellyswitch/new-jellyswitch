require "test_helper"

# Cross-tenant enforcement for the whole API (Api::V1::BaseController), tested
# through a member-facing endpoint (GET /api/v1/me). An authenticated user may
# only operate within their own operator regardless of the X-Operator-Subdomain
# header; platform staff (the `superadmin` boolean) are exempt.
class Api::V1::BaseControllerTenantTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)
    @rival    = create(:operator, subdomain: "rival")
  end

  def get_me(user, subdomain)
    token = JWT.encode(
      { user_id: user.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    get "/api/v1/me", headers: {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => subdomain,
    }
  end

  test "member can reach their own operator" do
    get_me(@member, @operator.subdomain)
    assert_response :success
  end

  test "member cannot target another operator via the subdomain header" do
    get_me(@member, @rival.subdomain)
    assert_response :forbidden
  end

  test "platform staff may target another operator" do
    @member.update!(superadmin: true)
    get_me(@member, @rival.subdomain)
    assert_response :success
  end
end
