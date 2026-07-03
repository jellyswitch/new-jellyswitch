require "test_helper"

# ADR 0019 cancellation behavior: a bundle pass is restored on cancel only when
# no sibling booking still needs the day; a purchased coverage pass is kept and
# becomes reusable.
class CancelReservationCoverageTest < ActiveSupport::TestCase
  setup { @op = operators(:cowork_tahoe); @loc = locations(:cowork_tahoe_location) }

  def included_room
    create(:room, operator: @op, location: @loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
  end

  test "cancelling one of two same-day included bookings does not strip the shared bundle pass" do
    ActsAsTenant.with_tenant(@op) do
      user = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      dpt  = create(:day_pass_type, operator: @op, location: @loc, included_meeting_room_minutes: 240)
      bundle = DayPassBundle.create!(user: user, operator: @op, location: @loc, day_pass_type: dpt,
                                     quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      day = (Date.current + 3)
      r1 = create(:reservation, user: user, room: room, minutes: 60, datetime_in: day.to_time + 9.hours)
      Billing::Reservations::RedeemBundlePass.call(reservation: r1, user: user, use_bundle_pass: true)
      assert_equal 4, bundle.reload.passes_remaining
      r2 = create(:reservation, user: user, room: room, minutes: 60, datetime_in: day.to_time + 11.hours)

      CancelReservation.call(reservation: r1)

      assert_equal 4, bundle.reload.passes_remaining, "pass stays — r2 still needs the day"
      assert user.day_passes.for_day(day).exists?, "the minted pass is kept for r2"
      # ledger row re-pointed to the surviving booking
      assert DayPassBundleRedemption.where(reservation_id: r2.id, kind: "reservation").exists?
    end
  end

  test "a purchased coverage pass survives cancel and becomes reusable" do
    ActsAsTenant.with_tenant(@op) do
      user = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      dpt  = create(:day_pass_type, operator: @op, location: @loc, included_meeting_room_minutes: 60, amount_in_cents: 4000)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 3).to_time + 9.hours)
      pass = create(:day_pass, user: user, billable: user, operator: @op, location: @loc,
                    day_pass_type: dpt, day: Date.current + 3, reservation: res)

      CancelReservation.call(reservation: res)

      assert DayPass.find_by(id: pass.id), "purchased pass is kept (not refunded)"
      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 6, location: @loc)
      assert_equal :reusable_pass, state.outcome
      assert_equal pass.id, state.reusable_pass.id
    end
  end
end
