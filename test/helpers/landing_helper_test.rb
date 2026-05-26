require "test_helper"

# Regression coverage for `LandingHelper#space_host_for` — the helper that
# decides whose name + photo appears in the auto-greeting chat bubble.
# Before this change the algorithm was role-based only and would fall
# back to the operator's oldest admin (the founder) regardless of who
# actually runs day-to-day at the location. That meant Trevor Pipkin
# (Untethered's founder) was the "space host" at Zephyr Cove even
# though he isn't the on-site host.
#
# The fix: a per-location `space_host_id` override. When set, it wins.
# When nil, the existing role-based algorithm runs unchanged.
class LandingHelperTest < ActionView::TestCase
  include LandingHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user_a   = users(:cowork_tahoe_admin)
    @user_b   = users(:cowork_tahoe_non_member)
  end

  test "returns nil when location is nil" do
    assert_nil space_host_for(nil)
  end

  test "uses the explicit space_host_id when set" do
    @location.update_column(:space_host_id, @user_b.id)
    assert_equal @user_b, space_host_for(@location)
  end

  test "falls back to the role-based algorithm when space_host_id is nil" do
    @location.update_column(:space_host_id, nil)
    # The existing algorithm returns *some* admin — we don't pin which one,
    # just confirm the override path didn't break the fallback path.
    assert_not_nil space_host_for(@location)
  end
end
