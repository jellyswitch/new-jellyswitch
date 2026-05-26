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
end
