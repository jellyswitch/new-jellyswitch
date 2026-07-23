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
end
