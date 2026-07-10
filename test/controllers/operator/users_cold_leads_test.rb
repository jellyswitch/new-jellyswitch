require "test_helper"

# Regression: same bug class as RecurringReservationPolicy#check_conflicts?.
# `authorize @users` in Operator::UsersController#cold_leads infers
# UserPolicy#cold_leads?, which was never defined — the cold-leads page
# 500'd with NoMethodError since it shipped.
class Operator::UsersColdLeadsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
  end

  test "admin can view cold leads" do
    log_in users(:cowork_tahoe_admin)

    get cold_leads_users_path, env: default_env

    assert_response :success
  end

  test "member is denied cold leads" do
    log_in users(:cowork_tahoe_member)

    get cold_leads_users_path, env: default_env

    assert_response :redirect
  end
end
