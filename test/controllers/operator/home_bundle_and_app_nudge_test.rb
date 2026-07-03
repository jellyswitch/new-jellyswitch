require "test_helper"

# The member web home must show a bundle holder their remaining passes with a
# "use a pass for today" button (the web surface that was missing — a bundle
# holder previously saw nothing on the web and "disappeared"). The button drives
# the same ConsumeOnEntry redeem; ADR 0017: it hands off to the app for the door.
class Operator::HomeBundleSectionTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    host! "#{@operator.subdomain}.example.com"
  end

  def create_bundle(user, passes: 3)
    DayPassBundle.create!(
      user: user, billable: user, operator: @operator, location: @location,
      day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: passes, passes_remaining: passes, purchased_at: Time.current,
    )
  end

  test "a bundle holder sees their passes and a 'use a pass today' button on home" do
    user = users(:cowork_tahoe_non_member) # approved, no subscription — bundle is their access
    create_bundle(user, passes: 3)
    log_in user

    get home_path, env: default_env

    assert_response :success
    assert_match "Your day passes", response.body
    assert_select "form[action=?]", redeem_today_day_passes_path
  end

  test "a covered member with no bundle sees no redeem button on home" do
    member = users(:cowork_tahoe_member) # active subscription, no bundle
    log_in member

    get home_path, env: default_env

    assert_response :success
    assert_select "form[action=?]", redeem_today_day_passes_path, count: 0
  end
end
