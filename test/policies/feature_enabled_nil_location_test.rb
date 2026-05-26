require "test_helper"

# Regression coverage for the email-confirmation-flow 500. When an admin
# (or superadmin) viewed any operator page without `current_location`
# set, the operator-nav layout would call `policy(:door).enabled?`, which
# called `location.door_integration_enabled?` on nil — exploding the
# whole layout render with NoMethodError.
#
# Every policy listed in `app/adapters/navigation/default.rb#admin_nav_items`
# whose `enabled?` reads a `location.X_enabled?` flag has the same bug.
# This parametrized test asserts none of them crashes when location is
# nil. We don't care about the return value (false vs nil) — just that
# the call doesn't raise.
class FeatureEnabledNilLocationTest < ActiveSupport::TestCase
  POLICIES_WITH_LOCATION_FEATURE_FLAGS = [
    DoorPolicy,
    AnnouncementPolicy,
    PostPolicy,
    EventPolicy,
    OfficePolicy,
    OfficeLeasePolicy,
    RoomPolicy,
    ChildcarePolicy,
    ChildcareReservationPolicy,
    ChildcareSlotPolicy,
  ]

  POLICIES_WITH_LOCATION_FEATURE_FLAGS.each do |policy_class|
    test "#{policy_class}#enabled? does not raise when location is nil" do
      context = UserContext.new(nil, operators(:cowork_tahoe), nil)
      policy  = policy_class.new(context, :record)

      assert_nothing_raised do
        policy.enabled?
      end
    end
  end
end
