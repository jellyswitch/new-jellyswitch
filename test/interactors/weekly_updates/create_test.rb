require "test_helper"

# WeeklyUpdateJob processes every operator × location in a single pass, so a
# mid-batch failure + Sidekiq retry (or a double-firing scheduler) used to
# re-create a weekly update — and a duplicate feed card — for every location it
# had already handled. WeeklyUpdates::Save is now idempotent per
# (location, week_start); these guard that.
class WeeklyUpdates::CreateTest < ActiveSupport::TestCase
  setup do
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @week_start = Time.current.beginning_of_week - 1.week
    @week_end   = Time.current.end_of_week - 1.week
  end

  def run_create
    ActsAsTenant.with_tenant(@operator) do
      WeeklyUpdates::Create.call(
        operator: @operator, location: @location,
        week_start: @week_start, week_end: @week_end,
      )
    end
  end

  def weekly_cards
    FeedItem.where(operator: @operator).where("blob->>'type' = ?", "weekly-update")
  end

  test "first run creates exactly one weekly update and one feed card" do
    assert_difference [-> { WeeklyUpdate.count }, -> { weekly_cards.count }], 1 do
      assert run_create.success?
    end
  end

  test "a second run for the same location and week adds nothing" do
    run_create

    assert_no_difference [-> { WeeklyUpdate.count }, -> { weekly_cards.count }] do
      result = run_create
      assert result.success?, "idempotent re-run should still succeed"
    end
  end
end
