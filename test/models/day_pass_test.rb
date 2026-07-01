# == Schema Information
#
# Table name: day_passes
#
#  id               :bigint(8)        not null, primary key
#  billable_type    :string
#  complimentary    :boolean          default(FALSE), not null
#  day              :date             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  billable_id      :bigint(8)
#  day_pass_type_id :integer
#  invoice_id       :integer
#  location_id      :integer
#  operator_id      :integer          default(1), not null
#  reservation_id   :bigint(8)
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
#  index_day_passes_on_reservation_id                 (reservation_id)
#
require 'test_helper'

class DayPassTest < ActiveSupport::TestCase
  setup do
    @day_pass = day_passes(:cowork_tahoe_day_pass)
  end

  test "responds to today? correctly when the day pass is for today" do
    @day_pass.update(day: Time.zone.today)

    assert @day_pass.today?
  end

  test "responds to today? correctly when the day pass is for tomorrow" do
    (1..31).map do |i|
      @day_pass.update(day: Time.zone.today + i.days)

      assert @day_pass.today? == false
    end
  end
end

class DayPassReservationLinkTest < ActiveSupport::TestCase
  test "a day pass optionally belongs to a reservation" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      loc  = locations(:cowork_tahoe_location)
      user = create(:user, operator: operator, original_location: loc, current_location: loc)
      dpt  = create(:day_pass_type, operator: operator, location: loc, included_meeting_room_minutes: 60)
      room = create(:room, operator: operator, location: loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60)
      dp   = create(:day_pass, user: user, billable: user, operator: operator, location: loc,
                    day_pass_type: dpt, day: Date.current, reservation: res)
      assert_equal res, dp.reload.reservation
    end
  end
end
