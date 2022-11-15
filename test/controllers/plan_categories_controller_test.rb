require 'test_helper'
require 'stripe_mock'

class PlanCategoriesControllerTest < ActionDispatch::IntegrationTest

  def stripe_helper
    StripeMock.create_test_helper
  end

  setup do
    @admin = users(:cowork_tahoe_admin)
    log_in @admin
    @plan = plans(:cowork_tahoe_full_time_plan)
    @plan_category = plan_categories(:private_desk_pod)
    @operator = operators(:cowork_tahoe)
    StripeMock.start
  end
  
  test "should get plan_categories index path" do
    get operator_admin_plan_categories_path, env: default_env
    assert :success
  end

  test "should get new plan_categories path" do
    get new_operator_admin_plan_category_path, env: default_env
    assert :success
  end

  test "should create a plan category" do
    @new_plan_category = PlanCategory.new
    post operator_admin_plan_categories_path(@new_plan_category), params: { plan_category: { name: "another new plan category", operator_id: @operator.id } }, env: default_env
    assert_not flash.empty?
    assert :success
  end

  test "should update plan_category" do
    put operator_admin_plan_category_path(@plan_category), params: { plan_category: { name: "an updated name", plan_ids: [@plan.id] } }, env: default_env
    assert :found
    assert_redirected_to operator_admin_plan_category_path(@plan_category)
  end

  test "should delete plan_category" do
    delete operator_admin_plan_category_path(@plan_category), env: default_env
    assert :success
    assert_redirected_to operator_admin_plan_categories_path
  end

  test "should remove_plan from plan_category" do
    get operator_admin_plan_category_remove_plan_path(@plan_category), params: { plan_id: @plan.id }, env: default_env
    assert :success
    assert_redirected_to operator_admin_plan_category_path(@plan_category)
  end

  test "should get show plan_category path" do
    get operator_admin_plan_category_path(@plan_category), env: default_env
    assert :success
  end

end
