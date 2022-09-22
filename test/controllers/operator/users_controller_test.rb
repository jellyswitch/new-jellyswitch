require "test_helper"

class Operator::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_member)
    log_in @user
  end

  test "delete a user account(web)" do
    delete "/users/#{@user.id}", params: { user_id: @user.id }, env: default_env
    assert_redirected_to signup_path
  end

  test "delete a user account(ios)" do
    delete "/users/#{@user.id}", params: { user_id: @user.id }, env: ios_env
    assert_redirected_to signup_path
  end
end