require "test_helper"

# A member can pause a membership from the app in three taps and was never told
# what it cost them. A Tahoe Longhouse member paused a Dedicated Desk this way
# on 2026-08-19 and left their belongings behind without a word.
#
# The warning is the location's own house rule (web Settings → Edit Location),
# delivered on the subscription so the app can gate the pause behind it. Blank
# means the space has nothing to say about pausing — no popup, flow unchanged.
class Api::V1::PauseWarningTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)

    ActsAsTenant.with_tenant(@operator) do
      @plan = Plan.create!(
        name: "Dedicated Desk",
        operator: @operator,
        location: @location,
        plan_type: "individual",
        interval: "monthly",
        amount_in_cents: 30_000,
        available: true,
        visible: true,
      )
      @subscription = Subscription.create!(
        plan: @plan,
        subscribable: @member,
        billable: @member,
        active: true,
        start_date: 1.month.ago,
      )
    end
  end

  def headers
    token = JWT.encode(
      { user_id: @member.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def my_subscription
    get "/api/v1/my_subscription", headers: headers
    assert_response :success
    JSON.parse(response.body)
  end

  test "the location's pause warning rides along on the subscription" do
    warning = "Heads up! If you have belongings stored at a dedicated desk, pausing your " \
              "membership means giving up that desk. Please remove all of your belongings. " \
              "Anything left behind will be stored for up to 3 months before being disposed of."
    @location.update!(pause_warning: warning)

    assert_equal warning, my_subscription["pause_warning"]
  end

  test "a location with no warning sends nil, so the app pauses straight through" do
    @location.update!(pause_warning: nil)
    assert_nil my_subscription["pause_warning"]
  end

  test "a blank warning is treated as no warning, not an empty popup" do
    @location.update!(pause_warning: "   ")
    assert_nil my_subscription["pause_warning"],
      "whitespace must not surface as an empty confirmation dialog"
  end

  test "the warning is advisory — a member who accepts it still pauses" do
    @location.update!(pause_warning: "Give up your desk.")

    # The gate lives in the client. The server must keep honoring the pause, or
    # accepting the warning would dead-end.
    CreatePause.stub(:call, Interactor::Context.build(success: true)) do
      post "/api/v1/subscriptions/#{@subscription.id}/pause",
           params: { resumes_at: 30 }.to_json, headers: headers
    end

    assert_response :success
    assert JSON.parse(response.body)["success"]
  end
end
