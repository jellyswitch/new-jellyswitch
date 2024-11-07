require 'test_helper'

class Operator::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @user = users(:cowork_tahoe_member)
    @old_user = @user.dup
    log_in @user

    StripeMock.start

    setup_stripe
  end

  teardown do
    StripeMock.stop
  end

  test "should redirect to user show after user update" do
    patch user_path(@user, params: { user: { name: "New Name" } }), env: default_env
    assert_redirected_to user_path(@user)
  end

  test "should update the user with given params" do
    patch user_path(@user, params: { user: { name: "New Name" } }), env: default_env
    assert_equal "New Name", @user.reload.name
  end

  test "should scrub user data and redirect to signup page if user is not part of an organization" do
    @user.update(organization_id: nil)
    @user.reload.organization_id
    delete user_path(@user.id), env: default_env
    @user.reload
    assert @old_user.name != @user.name
    assert @old_user.bio != @user.bio
    assert_redirected_to signup_path
  end

  test "should NOT scrub user data and redirect to signup page if user is still in organization" do
    @user = users(:cowork_tahoe_admin) # org owner
    @old_user = @user.dup
    delete user_path(@user.id), env: default_env
    @user.reload
    assert @old_user.name == @user.name
    assert @old_user.bio == @user.bio
    assert_redirected_to root_path
  end

  test "should get search results and render index template" do
    @user.update(role: :admin, managed_locations: [locations(:cowork_tahoe_location)])
    User.reindex

    get search_users_path(params: { query: @user.name }), env: default_env
    assert_response :success
    assert_template :index
  end
end
