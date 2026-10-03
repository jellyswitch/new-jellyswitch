require "test_helper"

# GET/PATCH /api/v1/admin/organizations/:id — by-id lookups must stay inside
# the caller's operator and, for non-superadmins, their location boundary
# (managed locations + home location; legacy no-location groups stay visible).
# Cross-operator was already caught by acts_as_tenant; cross-location was not.
class Api::V1::Admin::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)       # manages cowork_tahoe_location
    @owner    = users(:cowork_tahoe_superadmin)  # role superadmin → every location
    @org      = organizations(:sierra_nevada_organization)

    @rival = create(:operator, subdomain: "rival")
    @rival_org = ActsAsTenant.with_tenant(@rival) do
      create(:organization, operator: @rival, name: "Rival Group")
    end
  end

  def headers_for(user)
    token = JWT.encode(
      { user_id: user.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  # A second location in @operator, created without hitting the geocoder.
  def create_unmanaged_location
    Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(@operator) { create(:location, operator: @operator) }
    end
  end

  test "show returns a same-operator group" do
    get "/api/v1/admin/organizations/#{@org.id}", headers: headers_for(@admin)

    assert_response :success, response.body
    assert_equal @org.id, response.parsed_body["id"]
  end

  test "show 404s for another operator's group" do
    get "/api/v1/admin/organizations/#{@rival_org.id}", headers: headers_for(@admin)

    assert_response :not_found
    assert_nil response.parsed_body["name"]
  end

  test "update renames a same-operator group" do
    patch "/api/v1/admin/organizations/#{@org.id}", headers: headers_for(@admin),
          params: { name: "Renamed Group" }.to_json

    assert_response :success, response.body
    assert_equal "Renamed Group", @org.reload.name
  end

  test "update 404s for another operator's group and leaves it untouched" do
    patch "/api/v1/admin/organizations/#{@rival_org.id}", headers: headers_for(@admin),
          params: { name: "Hijacked" }.to_json

    assert_response :not_found
    assert_equal "Rival Group", @rival_org.reload.name
  end

  test "show 404s for a group at a location the admin doesn't manage" do
    @org.update_columns(location_id: create_unmanaged_location.id)

    get "/api/v1/admin/organizations/#{@org.id}", headers: headers_for(@admin)

    assert_response :not_found
  end

  test "superadmin role sees groups at every location in the operator" do
    @org.update_columns(location_id: create_unmanaged_location.id)

    get "/api/v1/admin/organizations/#{@org.id}", headers: headers_for(@owner)

    assert_response :success, response.body
  end

  test "legacy groups with no location stay reachable" do
    @org.update_columns(location_id: nil)

    get "/api/v1/admin/organizations/#{@org.id}", headers: headers_for(@admin)

    assert_response :success, response.body
  end
end
