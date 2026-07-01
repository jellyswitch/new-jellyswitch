require "test_helper"

class Billing::Reservations::BuyCoverageDayPassTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe); @location = locations(:cowork_tahoe_location)
  end

  test "buys a day pass for the reservation date and links it" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      type = create(:day_pass_type, operator: @operator, location: @location,
                    included_meeting_room_minutes: 60, amount_in_cents: 4000, available: true, visible: true)
      res  = create(:reservation, user: user, room: room, minutes: 60,
                    datetime_in: (Date.current + 3).to_time + 9.hours)

      # Stub the day-pass purchase (Stripe) — this tests BuyCoverageDayPass's
      # orchestration + linking, not CreateDayPass's charge path.
      fake_create = lambda do |**_kwargs|
        DayPass.create!(user: user, billable: user, operator: @operator, location: @location,
                        day_pass_type: type, day: (Date.current + 3), imported: true)
        Struct.new(:success?, :message).new(true, nil)
      end

      result = Billing::DayPasses::CreateDayPass.stub(:call, fake_create) do
        Billing::Reservations::BuyCoverageDayPass.call(
          reservation: res, user: user, buy_day_pass: true, day_pass_type: type, location: @location)
      end

      assert_equal :bought, result.outcome
      dp = user.day_passes.for_day(Date.current + 3).first
      assert dp, "a day pass exists for the reservation date"
      assert_equal res.id, dp.reload.reservation_id
    end
  end

  test "no-op unless buy_day_pass" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      res = create(:reservation, user: user, room: create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true), minutes: 60)
      result = Billing::Reservations::BuyCoverageDayPass.call(reservation: res, user: user, buy_day_pass: false)
      assert_nil result.outcome
    end
  end
end
