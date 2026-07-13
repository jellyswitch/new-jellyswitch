# == Schema Information
#
# Table name: day_pass_types
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(FALSE), not null
#  amount_in_cents               :integer          default(0), not null
#  available                     :boolean          default(TRUE), not null
#  code                          :string
#  default_for_room_booking      :boolean          default(FALSE), not null
#  included_meeting_room_minutes :integer
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0), not null
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          not null
#
# Indexes
#
#  index_day_pass_types_on_location_id  (location_id)
#  index_dpt_on_op_loc_default          (operator_id,location_id,default_for_room_booking)
#
require "test_helper"

class DayPassTypeTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_member)
  end

  test "DayPassType.all_options_for_select returns all available day pass types for user with billing" do
    @user.stub(:has_billing_for_location?, true) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available
    end
  end

  test "DayPassType.all_options_for_select returns only free day pass types for user without billing" do
    @user.stub(:has_billing_for_location?, false) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available.free
    end
  end

  # --- daily_limit (per-day sales cap) ---

  test "daily_limit must be a positive integer when present" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.daily_limit = 0
    assert_not dpt.valid?
    dpt.daily_limit = 2
    assert dpt.valid?
    dpt.daily_limit = nil
    assert dpt.valid?, "nil daily_limit means unlimited and must be valid"
  end

  test "daily_limit_reached? is always false when no limit is set" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    assert_nil dpt.daily_limit
    assert_not dpt.daily_limit_reached?(day: Date.current, location: @location)
  end

  test "daily_limit_reached? counts every pass of the type on that day at that location" do
    operator = operators(:cowork_tahoe)
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.update!(daily_limit: 2)
    day = Date.current + 3

    ActsAsTenant.with_tenant(operator) do
      # 1st pass: a normal purchased pass
      DayPass.create!(user: @user, billable: @user, operator: operator,
                      location: @location, day_pass_type: dpt, day: day, imported: true)
      assert_not dpt.daily_limit_reached?(day: day, location: @location),
                 "1 of 2 is under the limit"

      # 2nd pass: complimentary — still counts (limit models physical capacity)
      other = users(:cowork_tahoe_non_member)
      DayPass.create!(user: other, billable: other, operator: operator,
                      location: @location, day_pass_type: dpt, day: day,
                      complimentary: true, imported: true)
      assert dpt.daily_limit_reached?(day: day, location: @location),
             "2 of 2 reaches the limit; complimentary passes count"

      # Different day and different location are unaffected
      assert_not dpt.daily_limit_reached?(day: day + 1, location: @location)
      other_location = Location.where.not(id: @location.id).first ||
        Location.create!(operator: operator, name: "Other Location")
      assert_not dpt.daily_limit_reached?(day: day, location: other_location)
    end
  end
end
