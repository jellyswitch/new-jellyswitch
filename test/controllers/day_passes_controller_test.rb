require "test_helper"
require 'stripe_mock'

class DayPassesControllerTest < ActionDispatch::IntegrationTest

  def stripe_helper
    StripeMock.create_test_helper
  end

  setup do
    @member = users(:cowork_tahoe_member)
    log_in @member
    @day_pass = day_passes(:cowork_tahoe_day_pass)
    @day_pass_type = day_pass_type(:cowork_tahoe_day_pass_type)
    StripeMock.start
  end

  test "should create a new day pass" do
    post day_passes_path, params: { day_pass: { day: Date.today.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type, user: @member } }, env: default_env
    follow_redirect!(env: default_env)
    assert_redirected_to choose_path
  end

  test "should get new day pass path" do
    get new_day_pass_path, params: { day_pass_type_id: @day_pass_type.id }, env: default_env
    assert :success
  end

  test "should get day passes index path" do
    get day_passes_path, env: default_env
    assert :success
  end

  test "should get day pass show path" do
    get day_pass_path(@day_pass), env: default_env
    assert :success
  end

  test "should get day pass code path" do
    get code_day_passes_path, env: default_env
    assert :succes
  end
end