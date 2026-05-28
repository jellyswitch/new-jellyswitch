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
end
