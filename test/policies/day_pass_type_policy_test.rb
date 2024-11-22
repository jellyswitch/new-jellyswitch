require "test_helper"

class DayPassTypePolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_permit @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def show?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_permit @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def edit?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_not_permitted @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def new?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_not_permitted @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def create?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_not_permitted @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def update?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_not_permitted @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end

  def destroy?
    assert_not_permitted @member, DayPassType
    assert_permit @admin, DayPassType
    assert_not_permitted @community_manager, DayPassType
    assert_permit @general_manager, DayPassType
  end
end