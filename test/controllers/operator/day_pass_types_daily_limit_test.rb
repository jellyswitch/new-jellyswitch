require "test_helper"

# Web-only config surface for the day-pass daily limit (spec:
# docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md).
class Operator::DayPassTypesDailyLimitTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @type = day_pass_type(:cowork_tahoe_day_pass_type)
    log_in users(:cowork_tahoe_admin)
  end

  test "admin sets a daily limit via update" do
    patch day_pass_type_path(@type),
          params: { day_pass_type: { name: @type.name, daily_limit: "2" } },
          env: default_env

    assert_equal 2, @type.reload.daily_limit
  end

  test "blank daily limit means unlimited (normalized to nil)" do
    @type.update!(daily_limit: 3)

    patch day_pass_type_path(@type),
          params: { day_pass_type: { name: @type.name, daily_limit: "" } },
          env: default_env

    assert_nil @type.reload.daily_limit
  end

  test "admin creates a type with a daily limit" do
    post day_pass_types_path,
         params: { day_pass_type: { name: "Day Office", amount_in_cents: "100", daily_limit: "2" } },
         env: default_env

    created = DayPassType.order(:id).last
    assert_equal "Day Office", created.name
    assert_equal 2, created.daily_limit
  end
end
