require "test_helper"

# Regression: Tahoe Longhouse "booted to sign-in". A single-location operator must
# ALWAYS resolve current_location to its one location — there is nothing to choose.
#
# SessionsHelper#current_location used a mutually-exclusive if/elsif chain where a
# *present but unresolvable* signal (a stale/cross-operator session, cookie, or
# saved `users.current_location_id`) won its branch, resolved to nil, and
# short-circuited the `locations.count == 1` auto-select fallback. current_location
# then returned nil, reset_location logged the user out, and they landed on the
# sign-in/landing page even though the operator has a single location.
class Operator::CurrentLocationResolutionTest < ActionController::TestCase
  tests Operator::RoomsController

  setup do
    setup_initial_user_fixtures
    @request.host = "#{operators(:cowork_tahoe).subdomain}.example.com"
  end

  test "single-location operator resolves its location despite a stale session location id" do
    user = users(:cowork_tahoe_admin) # cowork_tahoe is a single-location operator

    # Stale session location id (e.g. a deleted/foreign location) — present, but
    # not resolvable within this tenant.
    get :index, session: { user_id: user.id, location_id: 999_999 }

    # The single location auto-resolves: the page renders and the user is NOT
    # logged out / bounced to the landing page.
    assert_response :success
    assert_not_nil session[:user_id], "user should stay signed in"
  end
end
