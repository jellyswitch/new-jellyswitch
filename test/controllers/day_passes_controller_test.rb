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
  end

  test "should create a new day pass" do
    mock = Minitest::Mock.new

    mock.expect(:success?, true)
    mock.expect(:day_pass, @user.day_passes.last)
    mock.expect(:invoice, invoices(:paid_invoice))

    CreateInvoice.stub :call, mock do
      post day_passes_path, params: { day_pass: { day: Date.today.strftime('%a, %e %b %Y '), day_pass_type: @day_pass_type.id, user: @user } }, env: default_env
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