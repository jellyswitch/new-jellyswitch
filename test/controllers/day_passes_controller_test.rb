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
    mock = Minitest::Mock.new

    mock.expect(:success?, true)
    mock.expect(:day_pass, @user.day_passes.last)
    mock.expect(:invoice, invoices(:paid_invoice))

    CreateInvoice.stub :call, mock do
      post day_passes_path, params: { day_pass: { day: @date.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env
      assert_equal "Welcome to #{@user.operator.name}!", flash[:success]
      assert_redirected_to home_path
    end
  end

  test "should create a new day pass for the future" do
    @date = Time.zone.today + 2.days
    @date_formatted = @date.strftime("%m/%d/%Y")
    mock = Minitest::Mock.new

    mock.expect(:success?, true)
    mock.expect(:day_pass, @user.day_passes.last)
    mock.expect(:invoice, invoices(:paid_invoice))

    CreateInvoice.stub :call, mock do
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

  test "should get day pass show path" do
    get day_pass_path(@day_pass), env: default_env
    assert :success
  end

  test "should get day pass code path" do
    get code_day_passes_path, env: default_env
    assert :succes
  end
end
