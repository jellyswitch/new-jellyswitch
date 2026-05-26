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
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
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
