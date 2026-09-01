require "test_helper"

# Organizer-level coverage of the ADR 0019 commit path (request-level tests hit
# a pre-existing mocha+integration teardown quirk under PARALLEL_WORKERS=1).
class Billing::Reservations::CoverageBookingTest < ActiveSupport::TestCase
  setup do
    @op = operators(:cowork_tahoe)
    @loc = locations(:cowork_tahoe_location)
    # Room Credits are orthogonal to day-pass coverage — disable so ChargeCredits
    # doesn't demand a credit balance we're not testing here.
    @loc.update!(credits_enabled: false) if @loc.respond_to?(:credits_enabled)
  end

  def included_room
    create(:room, operator: @op, location: @loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
  end

  def call(user:, room:, **flags)
    di = (Date.current + 3).to_time.change(hour: 9)
    Billing::Reservations::CreateRoomReservation.call(
      reservation_params: { datetime_in: di, hours: 1.0, minutes: 60, room: room, amenity_ids: [] },
      user: user, location: @loc, day_pass_charge_info: nil, subscription_charge_info: nil,
      use_bundle_pass: false, use_existing_pass: false, buy_day_pass: false, day_pass_type: nil,
      enforce_coverage: true, **flags)
  end

  test "use_bundle_pass books an included room and covers the date" do
    ActsAsTenant.with_tenant(@op) do
      u = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      t = create(:day_pass_type, operator: @op, location: @loc, included_meeting_room_minutes: 120,
                 amount_in_cents: 4000, available: true, visible: true)
      DayPassBundle.create!(user: u, operator: @op, location: @loc, day_pass_type: t,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      r = call(user: u, room: room, use_bundle_pass: true)

      assert r.success?, "booking should succeed: #{r.message}"
      dp = u.day_passes.for_day((Date.current + 3)).first
      assert dp, "a bundle-minted pass covers the reservation date"
      assert_equal r.reservation.id, dp.reservation_id
      assert_equal 4, u.day_pass_bundles.first.reload.passes_remaining
    end
  end

  # ADR 0029 (Pratik incident): holding a bundle IS the coverage decision — a
  # flag-less member self-serve booking burns a pass automatically instead of
  # dead-ending in EnforceCoverage's 422 (the web calendar sheet sends no flags).
  test "a bundle holder with NO coverage decision books anyway — a pass burns automatically" do
    ActsAsTenant.with_tenant(@op) do
      u = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      t = create(:day_pass_type, operator: @op, location: @loc, included_meeting_room_minutes: 120,
                 amount_in_cents: 4000, available: true, visible: true)
      DayPassBundle.create!(user: u, operator: @op, location: @loc, day_pass_type: t,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      r = call(user: u, room: room) # no flags — the auto path

      assert r.success?, "booking should succeed: #{r.message}"
      dp = u.day_passes.for_day((Date.current + 3)).first
      assert dp, "a bundle-minted pass covers the reservation date"
      assert_equal 4, u.day_pass_bundles.first.reload.passes_remaining
    end
  end

  test "an included booking with NO coverage decision and NO bundle is blocked and rolled back" do
    ActsAsTenant.with_tenant(@op) do
      u = create(:user, operator: @op, original_location: @loc, current_location: @loc)
      room = included_room
      create(:day_pass_type, operator: @op, location: @loc, included_meeting_room_minutes: 120,
             amount_in_cents: 4000, available: true, visible: true)

      r = call(user: u, room: room) # no flags

      assert r.failure?
      assert_match(/day pass/i, r.message)
      assert_equal 0, Reservation.where(user: u, cancelled: false).count, "reservation rolled back"
      assert_equal 0, u.day_passes.count, "no silent auto-buy"
    end
  end

  # ADR 0019 web (P8): the new-card path (UpdateBillingAndCreateRoomReservation,
  # used when the web member enters a card) must carry the SAME coverage steps as
  # CreateRoomReservation, committed AFTER the reservation saves and BEFORE the
  # room/overage is charged. Lock the wiring so the card path can't silently
  # regress to the pre-ADR-0019 behavior (no burn / no enforce).
  test "both room-reservation organizers commit coverage before charging" do
    [Billing::Reservations::CreateRoomReservation,
     Billing::Reservations::UpdateBillingAndCreateRoomReservation].each do |organizer|
      steps = organizer.organized
      %i[ReuseCoveragePass RedeemBundlePass BuyCoverageDayPass EnforceCoverage].each do |k|
        assert_includes steps, Billing::Reservations.const_get(k), "#{organizer} missing #{k}"
      end
      save   = steps.index(Billing::Reservations::SaveRoomReservation)
      enforce = steps.index(Billing::Reservations::EnforceCoverage)
      charge = steps.index(Billing::Reservations::ChargeAtBooking)
      assert save < enforce, "#{organizer}: coverage must run after the reservation saves"
      assert enforce < charge, "#{organizer}: coverage must commit before ChargeAtBooking prices the room"
    end
  end
end
