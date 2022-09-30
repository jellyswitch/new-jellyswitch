require "test_helper"

class LeadPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end

  def test_new
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end

  def test_create
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end

  def test_edit
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end

  def test_update
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end

  def test_show
    assert_not_permitted @member, Lead
    assert_permit @admin, Lead
    assert_permit @community_manager, Lead
    assert_permit @general_manager, Lead
  end
end