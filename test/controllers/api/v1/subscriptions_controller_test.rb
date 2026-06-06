require "test_helper"

# Coverage for /api/v1/subscriptions/:id/upgrade — the endpoint the
# mobile MembershipScreen "Switch to This Plan" button hits.
#
# Pre-fix, calling upgrade on a paused subscription let SwitchMembership
# get all the way to Stripe::Subscription.update, which raises
# Stripe::InvalidRequestError ("Cannot update a subscription whose
# status is paused"). The exception bubbled up as a 500 / Internal
# server error on the mobile client. Now we short-circuit with an
# actionable 422 message.
class Api::V1::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member       = users(:cowork_tahoe_member)
    @operator     = operators(:cowork_tahoe)
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @new_plan     = plans(:cowork_tahoe_full_time_plan)

    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "upgrade on a paused subscription returns 422 with an unpause-first message instead of a 500" do
    @subscription.update!(paused: true)

    patch "/api/v1/subscriptions/#{@subscription.id}/upgrade",
          params: { plan_id: @new_plan.id }.to_json,
          headers: headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/paused.*unpause/i, body["error"].to_s,
      "expected an actionable 'unpause first' message instead of a 500")
    assert @subscription.reload.paused?, "the paused sub must stay paused"
  end

  test "upgrade to the plan you're already on returns 422 instead of a no-op switch" do
    assert_no_difference -> { @member.subscriptions.count } do
      patch "/api/v1/subscriptions/#{@subscription.id}/upgrade",
            params: { plan_id: @subscription.plan_id }.to_json,
            headers: headers
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_match(/already on/i, body["error"].to_s,
      "expected an actionable 'already on this plan' message")
    assert @subscription.reload.active?, "the existing subscription must be untouched"
  end

  test "upgrade to a costlier same-name plan is blocked (grandfathering)" do
    current  = @subscription.plan
    costlier = ActsAsTenant.with_tenant(@operator) do
      create(:plan, operator: @operator, location: current.location,
             name: current.name, amount_in_cents: current.amount_in_cents + 2500,
             plan_type: "individual", visible: true, available: true)
    end

    assert_no_difference -> { @member.subscriptions.count } do
      patch "/api/v1/subscriptions/#{@subscription.id}/upgrade",
            params: { plan_id: costlier.id }.to_json,
            headers: headers
    end

    assert_response :unprocessable_entity
    assert_match(/already on .*current price/i, JSON.parse(response.body)["error"].to_s)
    assert_equal current.id, @subscription.reload.plan_id, "member must stay on their grandfathered plan"
  end

  test "plans list hides a costlier same-name plan from an active member" do
    current  = @subscription.plan
    costlier = ActsAsTenant.with_tenant(@operator) do
      create(:plan, operator: @operator, location: current.location,
             name: current.name, amount_in_cents: current.amount_in_cents + 2500,
             plan_type: "individual", visible: true, available: true)
    end

    get "/api/v1/plans", headers: headers
    assert_response :success

    plan_ids = JSON.parse(response.body)["plans"].map { |p| p["id"] }
    assert_not_includes plan_ids, costlier.id, "costlier same-name plan must be hidden"
    assert_not_includes plan_ids, current.id, "the member's own plan isn't a switch target"
  end
end
