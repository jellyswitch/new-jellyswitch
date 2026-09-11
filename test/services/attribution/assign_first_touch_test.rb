require "test_helper"

class Attribution::AssignFirstTouchTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @user = users(:cowork_tahoe_member)
    @user.update_columns(acquired_at: nil, acquisition_channel: nil)
  end

  def visit(started_at:, user: nil, visitor_token: "vt-1", **attrs)
    Ahoy::Visit.create!(
      visit_token: SecureRandom.uuid, visitor_token: visitor_token, user: user,
      started_at: started_at, **attrs,
    )
  end

  test "walks back from the first logged-in visit to the earliest visit on the same visitor cookie" do
    visit(started_at: 10.days.ago, referrer: "https://www.google.com/", landing_page: "https://tml.jellyswitch.com/")
    visit(started_at: 2.days.ago, user: @user, referrer: nil, landing_page: "https://tml.jellyswitch.com/home")

    Attribution::AssignFirstTouch.call(@user)

    assert_equal "organic_search", @user.reload.acquisition_channel
    assert_equal "google.com", @user.acquisition_referrer
    assert_in_delta 10.days.ago, @user.acquired_at, 5
  end

  test "is frozen once assigned" do
    visit(started_at: 5.days.ago, user: @user, referrer: "https://www.google.com/")
    Attribution::AssignFirstTouch.call(@user)
    visit(started_at: 20.days.ago, visitor_token: "vt-1", referrer: "https://facebook.com/")

    Attribution::AssignFirstTouch.call(@user)
    assert_equal "organic_search", @user.reload.acquisition_channel

    Attribution::AssignFirstTouch.call(@user, force: true)
    assert_equal "social", @user.reload.acquisition_channel
  end

  test "uses the fallback visit for a brand-new signup and the surface when there is no visit" do
    v = visit(started_at: 1.minute.ago, landing_page: "https://tml.jellyswitch.com/signup?gclid=xyz")
    Attribution::AssignFirstTouch.call(@user, fallback_visit: v)
    assert_equal "paid_search", @user.reload.acquisition_channel
    assert_equal v.id, @user.acquisition_visit_id

    other = users(:cowork_tahoe_non_member)
    other.update_columns(acquired_at: nil)
    Attribution::AssignFirstTouch.call(other, surface: "app")
    assert_equal "app", other.reload.acquisition_channel
    assert_equal other.created_at.to_i, other.acquired_at.to_i
  end
end
