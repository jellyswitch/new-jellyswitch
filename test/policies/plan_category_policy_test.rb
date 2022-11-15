require "test_helper"

class PlanCategoryPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  def test_new
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  def test_show
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  def test_create
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  def test_update
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  def test_destroy
    assert_not_permitted @member, PlanCategory
    assert_permit @admin, PlanCategory
    assert_permit @community_manager, PlanCategory
    assert_permit @general_manager, PlanCategory
  end

  # def test_remove_plan
  #   assert_not_permitted @member, plans(:cowork_tahoe_full_time_plan)
  #   assert_permit @admin, plans(:cowork_tahoe_full_time_plan)
  #   assert_permit @community_manager, plans(:cowork_tahoe_full_time_plan)
  #   assert_permit @general_manager, plans(:cowork_tahoe_full_time_plan)
  # end
end