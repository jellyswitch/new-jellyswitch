require "test_helper"

# Scope enforcement for the admin API (Api::V1::Admin::BaseController).
#
# Admin endpoints pick the tenant from the X-Operator-Subdomain header and
# derive the location from the caller's own record, so without an explicit
# guard an operator admin could pull another operator's (cross-tenant) or
# another location's (cross-location) member data. These tests exercise the
# guard through POST /api/v1/admin/reports/member_csv (a concrete admin
# endpoint) and pin the two intended exceptions:
#
#   - Cross-tenant bypass: ONLY platform staff (the `superadmin` boolean).
#   - Cross-location bypass: ANY superadmin? (boolean OR role).
class Api::V1::Admin::BaseControllerScopeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)         # subdomain "tml"
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)        # role admin, admin:true, superadmin(bool):false, manages @location
    @owner    = users(:cowork_tahoe_superadmin)   # role superadmin, superadmin(bool):false (per-operator owner)
    @rival    = create(:operator, subdomain: "rival")
  end

  def headers_for(user, subdomain)
    token = JWT.encode(
      { user_id: user.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def post_member_csv(user, subdomain)
    post "/api/v1/admin/reports/member_csv", headers: headers_for(user, subdomain)
  end

  # A second location in @operator, created without hitting the geocoder.
  def create_unmanaged_location
    Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(@operator) { create(:location, operator: @operator) }
    end
  end

  test "admin exports their own operator" do
    assert_enqueued_with(job: MemberCsvExportJob, args: [@operator.id, nil, @admin.email]) do
      post_member_csv(@admin, @operator.subdomain)
    end
    assert_response :success
  end

  test "admin cannot target another operator via the subdomain header" do
    assert_no_enqueued_jobs only: MemberCsvExportJob do
      post_member_csv(@admin, @rival.subdomain)
    end
    assert_response :forbidden
  end

  test "per-operator superadmin role cannot cross tenants (boolean-only bypass)" do
    assert_equal false, @owner.superadmin, "fixture should have the boolean column false"
    assert @owner.superadmin?, "fixture should be a role-based superadmin"

    assert_no_enqueued_jobs only: MemberCsvExportJob do
      post_member_csv(@owner, @rival.subdomain)
    end
    assert_response :forbidden
  end

  test "platform staff (superadmin boolean) may cross tenants" do
    @admin.update!(superadmin: true)

    assert_enqueued_with(job: MemberCsvExportJob, args: [@rival.id, nil, @admin.email]) do
      post_member_csv(@admin, @rival.subdomain)
    end
    assert_response :success
  end

  test "admin confined to a location they do not manage is forbidden" do
    other_location = create_unmanaged_location
    @admin.update!(original_location: nil, current_location: other_location)
    refute @admin.manages_location?(other_location)

    assert_no_enqueued_jobs only: MemberCsvExportJob do
      post_member_csv(@admin, @operator.subdomain)
    end
    assert_response :forbidden
  end

  test "any superadmin? bypasses location scoping within their operator" do
    other_location = create_unmanaged_location
    @owner.update!(original_location: nil, current_location: other_location)
    refute @owner.manages_location?(other_location)

    assert_enqueued_with(job: MemberCsvExportJob, args: [@operator.id, nil, @owner.email]) do
      post_member_csv(@owner, @operator.subdomain)
    end
    assert_response :success
  end

  test "a general manager (hyphenated role, admin:false) may use the admin API" do
    gm = users(:cowork_tahoe_general_manager)
    assert_equal false, gm.admin, "fixture GM should not have the admin boolean"
    assert gm.general_manager?

    assert_enqueued_with(job: MemberCsvExportJob, args: [@operator.id, nil, gm.email]) do
      post_member_csv(gm, @operator.subdomain)
    end
    assert_response :success
  end

  test "a plain member cannot use the admin API" do
    member = users(:cowork_tahoe_member)
    refute member.admin?
    refute member.superadmin?

    assert_no_enqueued_jobs only: MemberCsvExportJob do
      post_member_csv(member, @operator.subdomain)
    end
    assert_response :forbidden
  end
end
