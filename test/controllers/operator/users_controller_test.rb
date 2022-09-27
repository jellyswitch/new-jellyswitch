require 'test_helper'

class Operator::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @user = users(:cowork_tahoe_member)
    log_in @user
  end

  test "should redirect to user show after user update" do
    patch user_path(@user, params: { user_params: { user: @user, name: "New Name" } } ), env: default_env
    assert_redirected_to user_path(@user)
  end

  test "should update the user with given params" do
    patch user_path(@user, params: { user: { id: @user.id, name: "New Name" } }), env: default_env
    assert_equal "New Name", @user.reload.name
  end
end
