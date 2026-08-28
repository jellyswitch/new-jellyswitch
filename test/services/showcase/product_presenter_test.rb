require "test_helper"

class Showcase::ProductPresenterTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
  end

  test "bundle bullets: pass count, per-day meeting time, hours-bound access" do
    type = DayPassType.new(name: "5-Pack", quantity: 5, amount_in_cents: 16_000,
                           included_meeting_room_minutes: 60, operator: @operator)
    tier = Showcase::ProductPresenter.new(type).tier

    assert_equal "$160", tier[:price_label]
    assert_includes tier[:bullets], "5 day passes"
    assert_includes tier[:bullets], "60 min meeting room time per day"
    assert_includes tier[:bullets], "Building access during open hours"
  end

  test "single pass with anytime access" do
    type = DayPassType.new(name: "Day Pass", quantity: 1, amount_in_cents: 4_000,
                           always_allow_building_access: true, operator: @operator)
    bullets = Showcase::ProductPresenter.new(type).tier[:bullets]

    refute bullets.any? { |b| b.include?("day passes") }
    assert_includes bullets, "Anytime building access"
  end

  test "plan bullets render enforced limits verbatim, then free-text features" do
    plan = Plan.new(name: "Flex", interval: "monthly", amount_in_cents: 22_500,
                    building_access_level: :business_hours, has_day_limit: true, day_limit: 10,
                    commitment_interval: 3, features: ["Free coffee"], operator: @operator)
    tier = Showcase::ProductPresenter.new(plan).tier

    assert_equal "$225/month", tier[:price_label]
    assert_equal ["10 days per month", "Building access during business hours",
                  "3-month minimum commitment", "Free coffee"], tier[:bullets]
  end

  test "no-access plan says so" do
    plan = Plan.new(name: "Mailbox", interval: "monthly", amount_in_cents: 2_500,
                    building_access_level: :none, operator: @operator)
    assert_includes Showcase::ProductPresenter.new(plan).tier[:bullets], "No building access included"
  end
end
