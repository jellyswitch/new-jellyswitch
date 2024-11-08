require "test_helper"

class UserPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_unapproved
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_archived
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_not_permitted @community_manager, User
    assert_not_permitted @general_manager, User
  end

  def test_show
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_about
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_childcare
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_credits
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_add_credits
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_add_childcare_reservations
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_ltv
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_usage
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_payment_method
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_membership
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_admin_day_passes
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_checkins
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_organization
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_admin_invoices
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_add_member
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_edit
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_edit_role
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_not_permitted @community_manager, User
    assert_permit @general_manager, User
  end

  def test_update
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_change_password
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_update_password
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_remove_from_organization
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_update_organization
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_memberships
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_day_passes
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_reservations
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_past_reservations
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_invoices
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_approve
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_unapprove
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_edit_billing
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_update_billing
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_archive
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end

  def test_unarchive
    assert_not_permitted @member, User
    assert_permit @admin, User
    assert_permit @community_manager, User
    assert_permit @general_manager, User
  end
end