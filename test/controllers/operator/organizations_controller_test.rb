require "test_helper"

# Regression: Tahoe Longhouse /organizations 500. Groups imported from
# OfficeRnD can be ownerless (`belongs_to :owner, optional: true`), but the
# index list partial called `organization.owner.name` unguarded, so ONE
# ownerless group took down the whole Groups page with NoMethodError on nil.
# The show page already guarded nil owners; the list partial now does too.
class Operator::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
  end

  test "index renders when a group has no owner" do
    Organization.create!(
      name: "Imported Ownerless LLC",
      operator: @operator,
      location: locations(:cowork_tahoe_location),
    )

    log_in @admin
    get "/organizations", env: default_env

    assert_response :success
    assert_includes response.body, "Imported Ownerless LLC"
    assert_includes response.body, "No owner assigned"
  end
  # Regression (Seth, Untethered Fulton, 2026-10-03): the show page's
  # Archive/Unarchive buttons PATCHed /organizations/:id/edit, which has no
  # PATCH route — every click 404'd and the group stayed put since 3/30.
  test "archive and unarchive buttons target the update route" do
    org = Organization.create!(name: "Archive Me LLC", operator: @operator, location: locations(:cowork_tahoe_location), owner: @admin)

    log_in @admin
    get organization_path(org), env: default_env
    assert_response :success
    assert_includes response.body, "Archive Group"
    assert_not_includes response.body, "#{edit_organization_path(org)}?organization"
    assert_includes response.body, %(href="#{organization_path(org, organization: { visible: false })}")
  end

  test "PATCH visible=false archives the group and visible=true restores it" do
    org = Organization.create!(name: "Archive Me LLC", operator: @operator, location: locations(:cowork_tahoe_location), owner: @admin)

    log_in @admin
    # Stripe customer sync isn't under test here.
    Operator.any_instance.stubs(:update_organization_customer_details).returns(true)

    patch organization_path(org, organization: { visible: false }), env: default_env
    assert_redirected_to organization_path(org)
    assert_not org.reload.visible?

    patch organization_path(org, organization: { visible: true }), env: default_env
    assert org.reload.visible?
  end

  # Seth (Untethered Fulton, 2026-10-03): the group "Add members" picker listed
  # every member of the operator, both spaces mixed. Now only the group's space.
  test "add members picker only lists members of the group's space" do
    other = locations(:cowork_tahoe_location).dup
    other.name = "Second Space"
    other.save!(validate: false)

    org = Organization.create!(name: "Here Group", operator: @operator, location: locations(:cowork_tahoe_location), owner: @admin)
    here  = User.create!(name: "Here Member", email: "here-member@example.com", phone: "5305550101", password: "password123",
                         operator: @operator, original_location: locations(:cowork_tahoe_location), approved: true)
    there = User.create!(name: "Other Space Member", email: "other-member@example.com", phone: "5305550102", password: "password123",
                         operator: @operator, original_location: other, approved: true)

    log_in @admin
    get organization_members_path(org), env: default_env
    assert_response :success
    assert_includes response.body, "Here Member (#{here.email})"
    assert_not_includes response.body, "Other Space Member (#{there.email})"
  end
end
