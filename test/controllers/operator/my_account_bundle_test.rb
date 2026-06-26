require "test_helper"

# A member's own "My Day Passes" page (My Account → View my day passes) must show
# their Day Pass Bundle balance + a use-a-pass affordance — not just redeemed
# passes. (Reported: the bundle only surfaced on the home page.)
class Operator::MyAccountBundleTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_non_member) # approved, no subscription
    host! "#{@operator.subdomain}.example.com"
  end

  def create_bundle(passes: 4)
    DayPassBundle.create!(
      user: @user, billable: @user, operator: @operator, location: @location,
      day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: passes, passes_remaining: passes, purchased_at: Time.current,
    )
  end

  test "My Day Passes shows the bundle balance and a use-a-pass button" do
    create_bundle(passes: 4)
    log_in @user

    get user_day_passes_path(@user), env: default_env

    assert_response :success
    assert_match "Your day passes", response.body
    assert_match "4", response.body
    assert_select "form[action=?]", redeem_today_day_passes_path
  end

  test "no bundle section when the member has no passes" do
    log_in @user

    get user_day_passes_path(@user), env: default_env

    assert_response :success
    assert_select "form[action=?]", redeem_today_day_passes_path, count: 0
  end
end
