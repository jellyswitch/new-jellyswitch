require "test_helper"

class Operator::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @organization = organizations(:sierra_nevada_organization)
    @user = users(:cowork_tahoe_community_manager)
    log_in @user
  end

  test "should update organization" do
    new_billing_owner = users(:cowork_tahoe_community_manager)

    params = { name: "New Name", website: "newwebsite.com", billing_contact_id: new_billing_owner.id }

    UpdateOrganization.stub(:call, -> { OpenStruct.new(success?: true) }) do
      @organization.update(params)
      @organization.save
    end

    patch organization_path(@organization, params: { organization: params }), env: default_env

    assert_redirected_to organization_path(@organization)
    assert_equal "The organization New Name has been updated.", flash[:notice]
  end
end
