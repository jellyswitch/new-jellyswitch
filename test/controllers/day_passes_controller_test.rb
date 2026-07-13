require "test_helper"
require 'stripe_mock'

class DayPassesControllerTest < ActionDispatch::IntegrationTest
  setup do
    StripeMock.start
    @user = users(:cowork_tahoe_member)
    log_in @user
    @day_pass = day_passes(:cowork_tahoe_day_pass)
    @day_pass_type = day_pass_type(:cowork_tahoe_day_pass_type)
    setup_stripe

    stub_request(:post, "https://fcm.googleapis.com/fcm/send")
      .to_return(
        status: 200
      )
  end

  teardown do
    WebMock.reset!
  end

  test "should create a new day pass for today" do
    @date = Time.zone.today
    result = OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: true, day: @date))

    Billing::DayPasses::CreateDayPass.stub :call, result do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env
      # Approved buyer also gets the email hand-off appended (see
      # Operator::HomeEmailHandoffTest); assert the base message is present.
      assert_includes flash[:success], "Welcome to #{@user.operator.name}!"
      assert_redirected_to home_path
    end
  end

  test "should create a new day pass for the future" do
    @date = Time.zone.today + 2.days
    @date_formatted = @date.strftime("%m/%d/%Y")
    result = OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: false, day: @date))

    Billing::DayPasses::CreateDayPass.stub :call, result do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env

      # Approved buyer also gets the email hand-off appended (see
      # Operator::HomeEmailHandoffTest); assert the base message is present.
      assert_includes flash[:success], "Thanks! Your day pass will be available on #{ @date_formatted }."
      assert_redirected_to home_path
    end
  end

  # Onboarding: an unapproved member who buys their way in should land on the
  # "You're almost in!" (/wait) confirmation, not home_path (which resolves to
  # the /choose Welcome screen and reads as "back to the purchase options").
  test "unapproved member is redirected to the awaiting-approval screen after purchase" do
    @user.update!(approved: false)
    @date = Time.zone.today
    result = OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: true, day: @date))

    Billing::DayPasses::CreateDayPass.stub :call, result do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env
      assert_redirected_to wait_path
    end
  end

  test "approved member still goes home after purchase" do
    @user.update!(approved: true)
    @date = Time.zone.today
    result = OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: true, day: @date))

    Billing::DayPasses::CreateDayPass.stub :call, result do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env
      assert_redirected_to home_path
    end
  end

  test "awaiting-approval screen renders with updated copy and options" do
    @user.update!(approved: false)
    get wait_path, env: default_env
    assert_response :success
    assert_match "a few minutes during business hours", response.body
  end

  test "should get new day pass path" do
    get new_day_pass_path, params: { day_pass_type_id: @day_pass_type.id }, env: default_env
    assert :success
  end

  test "should get day passes index path" do
    get day_passes_path, env: default_env
    assert :success
  end

  # Regression: production NoMethodError (Honeybadger #130571713) when
  # current_location was nil inside find_day_passes. The action must not
  # crash on `current_location.day_passes`.
  test "index redirects when current_location is nil for logged-in user" do
    Operator::DayPassesController.any_instance.stubs(:current_location).returns(nil)
    get day_passes_path, env: default_env
    assert_response :redirect
  end

  # Regression for the logged-out non-HTML path through reset_location, which
  # previously fell through and let the action run with a nil current_location.
  test "index halts cleanly when logged-out non-HTML hits with nil current_location" do
    Operator::DayPassesController.any_instance.stubs(:current_location).returns(nil)
    Operator::DayPassesController.any_instance.stubs(:logged_in?).returns(false)
    get day_passes_path(format: :json), env: default_env
    assert_response :unauthorized
  end

  test "should get day pass show path" do
    get day_pass_path(@day_pass), env: default_env
    assert :success
  end

  test "should get day pass code path" do
    get code_day_passes_path, env: default_env
    assert :succes
  end

  test "blocks self-serve purchase when the type's daily limit is reached" do
    target = Time.zone.today + 2.days
    @day_pass_type.update!(daily_limit: 1)
    other = users(:cowork_tahoe_non_member)
    ActsAsTenant.with_tenant(@user.operator) do
      DayPass.create!(user: other, billable: other, operator: @user.operator,
                      location: locations(:cowork_tahoe_location),
                      day_pass_type: @day_pass_type, day: target, imported: true)
    end

    assert_no_difference -> { DayPass.count } do
      post day_passes_path, params: { day_pass: {
        day_pass_type: @day_pass_type.id,
        "day(1i)" => target.year.to_s, "day(2i)" => target.month.to_s, "day(3i)" => target.day.to_s,
      } }, env: default_env
    end

    assert_redirected_to new_day_pass_path(day_pass_type_id: @day_pass_type.id)
    assert_includes flash[:error], "fully booked"
  end

  test "daily limit cannot be bypassed with a plain-string day param" do
    target = Time.zone.today + 2.days
    @day_pass_type.update!(daily_limit: 1)
    other = users(:cowork_tahoe_non_member)
    ActsAsTenant.with_tenant(@user.operator) do
      DayPass.create!(user: other, billable: other, operator: @user.operator,
                      location: locations(:cowork_tahoe_location),
                      day_pass_type: @day_pass_type, day: target, imported: true)
    end

    assert_no_difference -> { DayPass.count } do
      post day_passes_path, params: { day_pass: {
        day_pass_type: @day_pass_type.id,
        day: target.strftime('%a, %e %b %Y'),
      } }, env: default_env
    end

    assert_includes flash[:error], "fully booked"
  end
end
