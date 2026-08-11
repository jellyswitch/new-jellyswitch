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

  # A Day Office bundle spent on ROOM coverage mints a pass AND takes an office
  # for the day (ADR 0026). That office hold is a reservation by the same user,
  # at the same location, on the same day, in a $0 room — it matches every
  # clause of the coverage-survivor lookup. Left eligible, cancelling the
  # covered booking re-points the ledger at the hold and keeps the pass spent,
  # so the member silently loses a bundle pass for a booking they cancelled and
  # the "last booking releases the pass" rule can never fire. Holds are the
  # pass's own artifact, never coverage for it.
  test "an office hold does not count as a coverage survivor when the covered booking is cancelled" do
    ActsAsTenant.with_tenant(@op) do
      user = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      dpt = DayPassType.create!(operator: @op, location: @loc, name: "Office 5-Pack",
                                amount_in_cents: 20000, quantity: 5, kind: "day_office",
                                included_meeting_room_minutes: 240, available: true, visible: true)
      office = create(:room, operator: @op, location: @loc)
      dpt.assign_office_rooms!({ office.id => 1 })
      bundle = DayPassBundle.create!(user: user, operator: @op, location: @loc, day_pass_type: dpt,
                                     quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      day = Date.current + 3
      booking = create(:reservation, user: user, room: room, minutes: 60, datetime_in: day.to_time + 9.hours)
      result = Billing::Reservations::RedeemBundlePass.call(reservation: booking, user: user, use_bundle_pass: true)

      hold = result.office_hold
      minted = result.bundle_redemption_day_pass
      assert hold.present?, "sanity: an office bundle must take an office alongside the room coverage"
      assert_equal 4, bundle.reload.passes_remaining, "sanity: the booking burned a pass"

      CancelReservation.call(reservation: booking, mode: :member, current_user: user)

      assert_equal 5, bundle.reload.passes_remaining,
        "the bundle pass must be restored — the office hold is not a surviving booking"
      assert_nil DayPass.find_by(id: minted.id), "the minted coverage pass is destroyed"
      refute DayPassBundleRedemption.where(reservation_id: hold.id).exists?,
        "the redemption ledger must never be re-pointed at the office hold"
      # The hold goes with the pass that owned it: DayPass's before_destroy runs
      # DayOffices::ReleaseHold, so giving the day back gives the office back.
      assert hold.reload.cancelled, "releasing the pass releases its office too"
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
