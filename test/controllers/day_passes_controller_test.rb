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
      assert_equal "Welcome to #{@user.operator.name}!", flash[:success]
      assert_redirected_to home_path
    end
  end

  test "should create a new day pass for the future" do
    @date = Time.zone.today + 2.days
    @date_formatted = @date.strftime("%m/%d/%Y")
    result = OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: false, day: @date))

    Billing::DayPasses::CreateDayPass.stub :call, result do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env

      assert_equal "Thanks! Your day pass will be available on #{ @date_formatted }.", flash[:success]
      assert_redirected_to home_path
    end
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
end
