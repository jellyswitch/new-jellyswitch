require 'test_helper'
require 'stripe_mock'

class PlansControllerTest < ActionDispatch::IntegrationTest

  def stripe_helper
    StripeMock.create_test_helper
  end

  setup do
    @admin = users(:cowork_tahoe_admin)
    log_in @admin
    @plan = plans(:cowork_tahoe_full_time_plan)
    @operator = operators(:cowork_tahoe)
    @archived_plan = plans(:cowork_tahoe_archived_plan)
    StripeMock.start
  end

  test "should get plans index path" do
    get plans_path, env: default_env
    assert :success
  end

  test "should get new plan path" do
    get new_plan_path, env: default_env
    assert :success
  end

  test "should get archived plans path" do
    get archived_plans_path, env: default_env
    assert :success
  end

  test "should create a plan" do
    @new_plan = Plan.new
    post plans_path(@new_plan), params: { plan: { name: "another new plan", product: { name: "another new plan" }, operator_id: @operator.id, plan_type: "individual", slug: "another-new-plan", stripe_plan_id: "another-new-plan", amount_in_cents: 1000, interval: "monthly", description: "another brand new plan", add_plan: "Just add this plan" } }, env: default_env
    assert_not flash.empty?
    assert :success
  end

  test "should get edit plan path" do
    get edit_plan_path(@plan), env: default_env
    assert :success
  end

  test "should update plan" do
    put plan_path(@plan), params: { plan: { description: "an updated description" } }, env: default_env
    assert :found
    assert_redirected_to plan_path(@plan)
  end

  test "should delete plan" do
    delete plan_path(@plan), env: default_env
    assert :success
    assert_redirected_to plans_path
  end

  test "should get show plan path" do
    get plan_path(@plan), env: default_env
    assert :success
  end

  test "should unarchive plan" do
    post plan_unarchive_path(@archived_plan), env: default_env
    assert @archived_plan.available = true
    assert :success
  end

  test "should toggle visibility" do
    get plan_toggle_visibility_path(@plan), env: default_env
    assert :success
    assert_redirected_to plan_path(@plan)
  end

  test "should toggle availability" do
    get plan_toggle_availability_path(@plan), env: default_env
    assert :success
    assert_redirected_to plan_path(@plan)
  end

  test "should toggle building access" do
    get plan_toggle_building_access_path(@plan), env: default_env
    assert :success
    assert_redirected_to plan_path(@plan)
  end
end
