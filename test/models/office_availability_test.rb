require "test_helper"

# Office Inventory listing rule (2026-08-27 plan §8).
class OfficeAvailabilityTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @office = Office.create!(operator: @operator, location: @location, name: "Office A")
  end

  test "vacant visible office is available now" do
    assert_equal :now, @office.listed_availability
  end

  test "leased office is not listed until staff flip coming_available" do
    user = users(:cowork_tahoe_member)
    subscription = Subscription.create!(subscribable: user, billable: user,
                                        plan: @operator.plans.first, active: true,
                                        start_date: 1.month.ago)
    lease = OfficeLease.create!(operator: @operator, office: @office, location: @location,
                                user: user, subscription: subscription,
                                start_date: 1.month.ago, end_date: 2.months.from_now)
    assert_nil @office.reload.listed_availability

    @office.update!(coming_available: true)
    assert_equal lease.end_date, @office.reload.listed_availability
  end

  test "invisible office is never listed" do
    @office.update!(visible: false)
    assert_nil @office.listed_availability
  end
end
