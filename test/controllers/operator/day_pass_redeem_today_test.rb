require "test_helper"

# Web (operator namespace) member self-redeem of a bundle pass for "today".
# Mirrors the mobile API's POST /api/v1/day_passes/redeem_today: the SAME single
# authority (Billing::DayPassBundles::ConsumeOnEntry) — today-only, idempotent,
# and a no-op when other coverage already grants access.
#
# See ADR 0017: a redemption mints today's DayPass (the right to be present) but
# does NOT open a door — the success state hands off to the app.
class Operator::DayPassRedeemTodayTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_non_member) # no sub / lease / reservation / day pass
    host! "#{@operator.subdomain}.example.com"
  end

  def create_active_bundle(user, passes: 5)
    DayPassBundle.create!(
      user:               user,
      billable:           user,
      operator:           @operator,
      location:           @location,
      day_pass_type:      day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: passes,
      passes_remaining:   passes,
      purchased_at:       Time.current,
    )
  end

  test "bundle holder redeems a pass for today: burns one and mints today's DayPass" do
    bundle = create_active_bundle(@user)
    log_in @user

    assert_difference -> { DayPass.where(user: @user, location: @location, day: Date.current).count }, 1 do
      post redeem_today_day_passes_path, env: default_env
    end

    assert_equal 4, bundle.reload.passes_remaining
    assert flash[:success].present?, "a successful redeem should confirm the pass to the member"
  end

  test "redeeming twice the same day burns only one pass (idempotent)" do
    bundle = create_active_bundle(@user)
    log_in @user

    post redeem_today_day_passes_path, env: default_env
    post redeem_today_day_passes_path, env: default_env

    assert_equal 4, bundle.reload.passes_remaining, "second redeem must not burn another pass"
  end

  test "redeem with no bundle mints nothing and surfaces an error" do
    log_in @user

    assert_no_difference -> { DayPass.where(user: @user).count } do
      post redeem_today_day_passes_path, env: default_env
    end

    assert flash[:error].present?, "should explain there are no passes to redeem"
  end

  test "a subscription-covered member does not spend a bundle pass" do
    member = users(:cowork_tahoe_member) # carries the cowork_tahoe_subscription fixture
    bundle = create_active_bundle(member)
    log_in member

    post redeem_today_day_passes_path, env: default_env

    assert_equal 5, bundle.reload.passes_remaining, "subscription-covered member must not spend a pass"
  end

  # Bundle holders with no coverage today never reach home — landing_redirect
  # sends them to /choose (allowed_in? is false). The redeem card must render
  # there too, or the web has no self-redeem path for exactly the people who
  # need it (the Erin/Tiffany discoverability gap).
  test "bundle holder with no coverage sees the redeem card on the choose page" do
    create_active_bundle(@user)
    log_in @user

    get choose_path, env: default_env

    assert_response :success
    assert_match "Use a pass for today", response.body
    assert_match redeem_today_day_passes_path, response.body
  end

  test "choose page shows no redeem card without an active bundle" do
    log_in @user

    get choose_path, env: default_env

    assert_response :success
    refute_match "Use a pass for today", response.body
  end

  test "covered member still sees the redeem card on home" do
    member = users(:cowork_tahoe_member)
    create_active_bundle(member)
    log_in member

    get home_path, env: default_env

    assert_response :success
    assert_match "Use a pass for today", response.body
  end
end
