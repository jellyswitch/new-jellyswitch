require "test_helper"

class Operators::FinishStripeConnectTest < ActiveSupport::TestCase
  def setup
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @oauth_ok = {
      "stripe_user_id" => "acct_NEW123",
      "stripe_publishable_key" => "pk_test_new",
      "refresh_token" => "rt_new",
      "access_token" => "at_new",
    }
  end

  def stub_oauth!(body = @oauth_ok)
    HTTParty.stubs(:post).returns(body)
  end

  # The connect used to end with a call to the nonexistent
  # Plan#create_stripe_plan — any operator that HAD plans got a NoMethodError
  # flash on every (re)connect, after the credentials were already stored
  # (Tahoe Longhouse go-live, 2026-07-17). Now each Stripe-backed plan is
  # recreated on the just-connected account via CreateStripePlan.
  test "recreates each stripe-backed plan on the newly connected account" do
    stub_oauth!
    plans = @operator.plans.where.not(stripe_plan_id: [nil, ""])
    assert plans.any?, "fixture operator needs at least one stripe-backed plan"

    Billing::Plans::CreateStripePlan
      .expects(:call)
      .times(plans.count)
      .returns(stub(success?: true))

    result = Operators::FinishStripeConnect.call(
      stripe_code: "ac_123", operator: @operator, location: @location,
    )

    assert result.success?
    assert_equal "acct_NEW123", @operator.reload.stripe_user_id
    assert_equal "acct_NEW123", @location.reload.stripe_user_id
  end

  test "a plan that already exists on the account does not fail the connect" do
    stub_oauth!
    Billing::Plans::CreateStripePlan
      .stubs(:call)
      .returns(stub(success?: false, message: "Plan already exists."))
    Honeybadger.expects(:notify).never

    result = Operators::FinishStripeConnect.call(
      stripe_code: "ac_123", operator: @operator, location: @location,
    )

    assert result.success?
  end

  test "an unexpected per-plan failure is reported but never fails the connect" do
    stub_oauth!
    Billing::Plans::CreateStripePlan
      .stubs(:call)
      .returns(stub(success?: false, message: "boom"))
    Honeybadger.expects(:notify).at_least_once

    result = Operators::FinishStripeConnect.call(
      stripe_code: "ac_123", operator: @operator, location: @location,
    )

    assert result.success?
    assert_equal "acct_NEW123", @operator.reload.stripe_user_id
  end

  test "an oauth error still fails the connect" do
    stub_oauth!("error" => "invalid_grant", "error_description" => "Bad code")
    Billing::Plans::CreateStripePlan.expects(:call).never

    result = Operators::FinishStripeConnect.call(
      stripe_code: "ac_bad", operator: @operator, location: @location,
    )

    refute result.success?
    assert_equal "Bad code", result.message
  end
end
