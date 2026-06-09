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

  # #6 (web): the admin profile view surfaces a member's past chat threads
  # alongside the internal notes section (#5, already shipped).
  test "admin profile page shows a member's chat conversations and notes" do
    admin = users(:cowork_tahoe_admin)
    admin.update(password: "password")
    ActsAsTenant.default_tenant = admin.operator
    post login_path(params: { session: { email: admin.email, password: "password" } }), env: default_env

    member = users(:cowork_tahoe_member)
    MemberFeedback.create!(
      operator: operators(:cowork_tahoe),
      user: member,
      comment: "The wifi keeps dropping",
    )

    get user_path(member), env: default_env
    assert_response :success
    assert_select "[data-testid='conversations-section']"
    assert_select "[data-testid='notes-section']"
    assert_match "The wifi keeps dropping", response.body
  end

  # Web timeline: door punches hidden from Recent (except milestones), full
  # history under the Doors tab.
  test "web timeline hides door-punch noise in recent and shows it under doors" do
    admin = users(:cowork_tahoe_admin)
    admin.update(password: "password")
    ActsAsTenant.default_tenant = admin.operator
    post login_path(params: { session: { email: admin.email, password: "password" } }), env: default_env

    member = users(:cowork_tahoe_member)
    member.activities.delete_all
    t = Time.utc(2026, 1, 1, 9, 0)
    Activity.create!(user: member, operator: operators(:cowork_tahoe), kind: "subscription_started", occurred_at: t)
    Activity.create!(user: member, operator: operators(:cowork_tahoe), kind: "door_punch", occurred_at: t + 1.hour)  # milestone
    Activity.create!(user: member, operator: operators(:cowork_tahoe), kind: "door_punch", occurred_at: t + 2.hours) # noise

    get user_path(member, tab: "recent"), env: default_env
    assert_response :success
    # Exactly one door row in Recent (the milestone), not both.
    assert_equal 1, response.body.scan(/Entered/).size, "Recent should show only the milestone door punch"

    get user_path(member, tab: "doors"), env: default_env
    assert_response :success
    assert_equal 2, response.body.scan(/Entered/).size, "Doors tab should show every door punch"
  end
end
