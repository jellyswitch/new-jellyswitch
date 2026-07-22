require "test_helper"

# The "Comp a day" button posts to the nested route /users/:user_id/comp_days,
# where :user_id is the member's friendly_id slug (User#to_param), not a numeric
# id. A plain .find(params[:user_id]) raised RecordNotFound for every member.
class Operator::CompDaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @member   = users(:cowork_tahoe_member)
    host! "#{@operator.subdomain}.example.com"
  end

  test "comp-a-day works via the slug URL" do
    log_in @admin

    # Guard: the route must carry the slug, or this test proves nothing.
    assert_includes user_comp_days_path(@member), @member.slug
    assert_no_match(/\A\d+\z/, @member.slug)

    assert_difference -> { CompDay.count }, 1 do
      post user_comp_days_path(@member), params: { reason: "door reader down" }, env: default_env
    end

    assert_response :redirect
    comp = CompDay.order(:created_at).last
    assert_equal @member.id, comp.user_id
    assert_equal @admin.id, comp.granted_by_id
    assert_equal Date.current, comp.occurred_on
    assert_equal "door reader down", comp.reason
  end

  test "a member cannot comp themselves a day" do
    log_in @member

    assert_no_difference -> { CompDay.count } do
      post user_comp_days_path(@member), env: default_env
    end

    assert_response :redirect
    assert_match(/Not authorized/, flash[:alert])
  end
end
