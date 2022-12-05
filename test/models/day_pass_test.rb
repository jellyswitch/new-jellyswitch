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