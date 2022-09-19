require "test_helper"
require "stripe_mock"

class OrganizationPolicyTest < PolicyAssertions::Test

  def stripe_helper
    StripeMock.create_test_helper
  end

  setup do
    setup_initial_user_fixtures
    StripeMock.start
    @organization = organizations(:sierra_nevada_organization)

    customer = Stripe::Customer.create({
                                         email: @organization.email
                                       }, {
                                         api_key: @organization.operator.stripe_secret_key.to_s,
                                         stripe_account: @organization.operator.stripe_user_id
                                       })

    @organization.update(stripe_customer_id: customer.id)
  end


  def test_index
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_show
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_new
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_create
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_edit
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_update
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_destroy
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  # to-do test currently fails because of card_added? returns false
  # def test_credit_card
  #   assert_not_permitted @member, organizations(:sierra_nevada_organization)
  #   assert_permit @admin, organizations(:sierra_nevada_organization)
  #   assert_permit @community_manager, organizations(:sierra_nevada_organization)
  #   assert_permit @general_manager, organizations(:sierra_nevada_organization)
  #   assert_permit @superadmin, organizations(:sierra_nevada_organization)
  # end

  def test_out_of_band
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_billing
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_payment_method
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_members
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_leases
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_invoices
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end

  def test_ltv
    assert_not_permitted @member, Organization
    assert_permit @admin, Organization
    assert_permit @community_manager, Organization
    assert_permit @general_manager, Organization
    assert_permit @superadmin, Organization
  end
end