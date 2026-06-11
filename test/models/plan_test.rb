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

  # ---- Commitment Length (commitment_interval) ----

  # daily is a valid INTERVAL_OPTION but commitment_duration had no mapping for
  # it → nil → `start_date + nil` crashed subscription creation.
  test "commitment_duration covers the daily interval" do
    plan = plans(:cowork_tahoe_full_time_plan)
    plan.interval = "daily"
    plan.commitment_interval = 30
    assert_equal 30.days, plan.commitment_duration
  end

  test "commitment_duration is N billing periods for each real interval" do
    plan = plans(:cowork_tahoe_full_time_plan)
    plan.commitment_interval = 6
    plan.interval = "monthly";    assert_equal 6.months,  plan.commitment_duration
    plan.interval = "quarterly";  assert_equal 18.months, plan.commitment_duration
    plan.interval = "biannually"; assert_equal 36.months, plan.commitment_duration
    plan.interval = "annually";   assert_equal 6.years,   plan.commitment_duration
  end

  # commitment_interval = 0 (and nil) means "no commitment" — must not read as
  # present (0.present? is true in Ruby, which made cancel_at = start_date).
  test "has_commitment_interval? is false for nil and 0, true for >= 1" do
    plan = plans(:cowork_tahoe_full_time_plan)
    plan.commitment_interval = nil; refute plan.has_commitment_interval?
    plan.commitment_interval = 0;   refute plan.has_commitment_interval?
    plan.commitment_interval = 1;   assert plan.has_commitment_interval?
  end

  test "commitment_interval must be a positive integer when set" do
    plan = plans(:cowork_tahoe_full_time_plan)
    plan.commitment_interval = 0
    refute plan.valid?
    assert_includes plan.errors[:commitment_interval], "must be greater than or equal to 1"

    plan.commitment_interval = -3
    refute plan.valid?

    plan.commitment_interval = nil
    assert plan.valid?, plan.errors.full_messages.to_sentence
  end
end
