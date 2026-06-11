require "test_helper"

# A Comp Day is the admin "add a day back" override against a member's Day Pool
# (the per-plan monthly day limit). One row = one day returned to the member
# for the period containing `occurred_on`, scoped to a location, with an audit
# trail (who granted it).
class CompDayTest < ActiveSupport::TestCase
  setup do
    @member   = users(:cowork_tahoe_member)
    @admin     = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  test "is valid with user, operator, location, granted_by, and occurred_on" do
    comp = CompDay.new(
      user: @member, operator: @operator, location: @location,
      granted_by: @admin, occurred_on: Date.current, reason: "door reader was down",
    )
    assert comp.valid?, comp.errors.full_messages.to_sentence
  end

  test "requires a user" do
    comp = CompDay.new(operator: @operator, location: @location, occurred_on: Date.current)
    refute comp.valid?
    assert_includes comp.errors[:user], "must exist"
  end

  test "requires an occurred_on date" do
    comp = CompDay.new(user: @member, operator: @operator, location: @location, occurred_on: nil)
    refute comp.valid?
    assert_includes comp.errors[:occurred_on], "can't be blank"
  end

  test "for_period returns only comps whose occurred_on falls inside the window" do
    inside = CompDay.create!(user: @member, operator: @operator, location: @location,
                             granted_by: @admin, occurred_on: Date.new(2026, 6, 10))
    before = CompDay.create!(user: @member, operator: @operator, location: @location,
                             granted_by: @admin, occurred_on: Date.new(2026, 5, 31))
    after  = CompDay.create!(user: @member, operator: @operator, location: @location,
                             granted_by: @admin, occurred_on: Date.new(2026, 7, 1))

    window_start = Time.zone.local(2026, 6, 1)
    window_end   = Time.zone.local(2026, 7, 1)
    ids = CompDay.for_period(window_start, window_end).pluck(:id)

    assert_includes ids, inside.id
    refute_includes ids, before.id
    refute_includes ids, after.id, "window end is exclusive"
  end
end
