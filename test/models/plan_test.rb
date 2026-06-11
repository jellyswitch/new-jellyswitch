require "test_helper"

class PlanTest < ActiveSupport::TestCase
  # A day-limited plan with a 0 limit would block every member the moment it's
  # turned on (0 days allowed). Guard against that footgun.
  test "a day-limited plan requires day_limit of at least 1" do
    plan = plans(:cowork_tahoe_part_time_plan)
    plan.has_day_limit = true
    plan.day_limit = 0

    refute plan.valid?
    assert_includes plan.errors[:day_limit], "must be greater than or equal to 1"
  end

  test "a plan without a day limit may keep day_limit at 0" do
    plan = plans(:cowork_tahoe_full_time_plan)
    plan.has_day_limit = false
    plan.day_limit = 0

    assert plan.valid?, plan.errors.full_messages.to_sentence
  end
end
