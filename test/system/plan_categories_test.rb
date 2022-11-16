require "application_system_test_case"

class PlanCategoriesTest < ApplicationSystemTestCase
  setup do
    @user = users(:cowork_tahoe_non_member)
    @plan_with_category = plans(:cowork_tahoe_full_time_plan)
    StripeMock.start
  end

  test "'Become a Member' (from choose route) takes a non_member to plan categories index, if there are plan_categories" do
    log_in(@user)

    click_on "Become a member"

    assert_text "Plan Categories"
  end

  test "'Become a Member' (from choose route) takes a non_member to plans index, if there are no plan_categories" do
    log_in(@user)
    @plan_with_category.update(plan_category: nil)
    @plan_with_category.reload

    click_on "Become a member"

    assert_text "Plans"
  end
end
