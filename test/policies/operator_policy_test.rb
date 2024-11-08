require "test_helper"

class OperatorPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Operator
    assert_not_permitted @admin, Operator
    assert_not_permitted @community_manager, Operator
    assert_not_permitted @general_manager, Operator
    assert_permit @superadmin, Operator
  end

  def test_new
    assert_not_permitted @member, Operator
    assert_not_permitted @admin, Operator
    assert_not_permitted @community_manager, Operator
    assert_not_permitted @general_manager, Operator
    assert_permit @superadmin, Operator
  end

  def test_show
    assert_not_permitted @member, operators(:cowork_tahoe)
    assert_permit @admin, operators(:cowork_tahoe)
    assert_not_permitted @community_manager, operators(:cowork_tahoe)
    assert_permit @general_manager, operators(:cowork_tahoe)
    assert_permit @superadmin, operators(:cowork_tahoe)
  end

  def test_edit
    assert_not_permitted @member, operators(:cowork_tahoe)
    assert_not_permitted @admin, operators(:cowork_tahoe)
    assert_not_permitted @community_manager, operators(:cowork_tahoe)
    assert_not_permitted @general_manager, operators(:cowork_tahoe)
    assert_permit @superadmin, operators(:cowork_tahoe)
  end

  def test_update
    assert_not_permitted @member, operators(:cowork_tahoe)
    assert_not_permitted @admin, operators(:cowork_tahoe)
    assert_not_permitted @community_manager, operators(:cowork_tahoe)
    assert_not_permitted @general_manager, operators(:cowork_tahoe)
    assert_permit @superadmin, operators(:cowork_tahoe)
  end

  def test_create
    assert_not_permitted @member, Operator
    assert_not_permitted @admin, Operator
    assert_not_permitted @community_manager, Operator
    assert_not_permitted @general_manager, Operator
    assert_permit @superadmin, Operator
  end

  def test_demo_instance
    assert_not_permitted @member, Operator
    assert_not_permitted @admin, Operator
    assert_not_permitted @community_manager, Operator
    assert_not_permitted @general_manager, Operator
    assert_permit @superadmin, Operator
  end

  def test_destroy
    assert_not_permitted @member, Operator
    assert_not_permitted @admin, Operator
    assert_not_permitted @community_manager, Operator
    assert_not_permitted @general_manager, Operator
    assert_permit @superadmin, Operator
  end
end