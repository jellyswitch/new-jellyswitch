require "test_helper"

# Bundles only began logging their own timeline card when the card started
# reporting passes-used and hours-booked. Packs bought before that need the
# backfill, or the member's history shows the burned day passes with no pack
# they came from.
class BackfillActivitiesJobBundlesTest < ActiveJob::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type   = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                    amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    end
  end

  def build_bundle(purchased_at:)
    ActsAsTenant.with_tenant(@operator) do
      DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                            day_pass_type: @type, quantity_purchased: 5, passes_remaining: 5,
                            purchased_at: purchased_at)
    end
  end

  def bundle_activities(bundle)
    Activity.where(kind: "day_pass_bundle", subject_type: "DayPassBundle", subject_id: bundle.id)
  end

  test "backfills a card for a pack that predates bundle activity logging" do
    purchased_at = 30.days.ago
    bundle = build_bundle(purchased_at: purchased_at)
    bundle_activities(bundle).delete_all # as if bought before the card existed

    BackfillActivitiesJob.perform_now(@operator.id)

    activity = bundle_activities(bundle).sole
    assert_equal 5, activity.payload["quantity"]
    assert_in_delta purchased_at, activity.occurred_at, 1.second
  end

  test "does not double up on a pack that already has a card" do
    bundle = build_bundle(purchased_at: 10.days.ago)
    assert_equal 1, bundle_activities(bundle).count

    BackfillActivitiesJob.perform_now(@operator.id)

    assert_equal 1, bundle_activities(bundle).count
  end
end
