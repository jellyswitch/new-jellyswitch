require "test_helper"

# Grandfathering: a member keeps the price of the tier they hold. Tiers are
# matched by plan NAME, so an active member is never offered/allowed a costlier
# same-name plan (e.g. $200 "Flex Membership" -> $225 "Flex Membership"), but
# may still switch to a genuinely different tier.
class PlanGrandfatherTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def plan(name:, cents:)
    ActsAsTenant.with_tenant(@operator) do
      create(:plan, operator: @operator, location: @location,
             name: name, amount_in_cents: cents, plan_type: "individual")
    end
  end

  test "blocks_switch_from? blocks the same plan (no-op)" do
    p = plan(name: "Flex Membership", cents: 20_000)
    assert p.blocks_switch_from?(p)
  end

  test "blocks_switch_from? blocks a costlier same-name plan" do
    current  = plan(name: "Flex Membership", cents: 20_000)
    costlier = plan(name: "Flex Membership", cents: 22_500)
    assert costlier.blocks_switch_from?(current)
  end

  test "blocks_switch_from? allows a cheaper same-name plan" do
    current = plan(name: "Flex Membership", cents: 22_500)
    cheaper = plan(name: "Flex Membership", cents: 20_000)
    refute cheaper.blocks_switch_from?(current)
  end

  test "blocks_switch_from? allows a different tier" do
    current = plan(name: "Flex Membership", cents: 20_000)
    other   = plan(name: "Full Time Membership", cents: 30_000)
    refute other.blocks_switch_from?(current)
  end

  test "blocks_switch_from? allows when the member has no current plan" do
    refute plan(name: "Flex Membership", cents: 20_000).blocks_switch_from?(nil)
  end

  test "switchable_from drops the current plan and costlier same-name plans" do
    current  = plan(name: "Flex Membership", cents: 20_000)
    costlier = plan(name: "Flex Membership", cents: 22_500)
    cheaper  = plan(name: "Flex Membership", cents: 18_000)
    other    = plan(name: "Full Time Membership", cents: 30_000)

    ids = Plan.where(id: [current, costlier, cheaper, other]).switchable_from(current).pluck(:id)

    assert_not_includes ids, current.id
    assert_not_includes ids, costlier.id
    assert_includes ids, cheaper.id
    assert_includes ids, other.id
  end

  test "switchable_from with nil applies no exclusions" do
    a = plan(name: "Flex Membership", cents: 20_000)
    b = plan(name: "Full Time Membership", cents: 30_000)
    ids = Plan.where(id: [a, b]).switchable_from(nil).pluck(:id)
    assert_includes ids, a.id
    assert_includes ids, b.id
  end
end
