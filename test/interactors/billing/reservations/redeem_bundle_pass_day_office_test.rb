require "test_helper"

# A Day Office bundle spent as ROOM COVERAGE still spends an office day, so
# the reserve-time burn takes an office too (ADR 0026). The subtle part is
# that two different reservations now hang off one minted pass and must not be
# confused: `day_pass.reservation` is the member's covered booking (ADR 0019),
# while the office hold is reachable only through
# reservations.day_office_pass_id.
class Billing::Reservations::RedeemBundlePassDayOfficeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def day_office_push_types
    enqueued_jobs.select { |j| j[:job] == SendNotificationsJob }
                 .map { |j| j[:args].last }
                 .grep(/DayOffice/)
  end

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @day = Date.current + 3
  end

  # Returns [member, bundle, booking, room_a, room_b].
  def setup_office_booking
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, room_a, room_b = make_office_bundle(member: member)
      # A free meeting room, deliberately NOT in the office pool — the booking
      # and the hold must be able to coexist.
      meeting_room = create(:room, operator: @operator, location: @location,
                            hourly_rate_in_cents: 0, include_with_day_pass: true)
      booking = create(:reservation, user: member, room: meeting_room, minutes: 60,
                       datetime_in: @day.to_time + 9.hours)
      [member, bundle, booking, room_a, room_b]
    end
  end

  test "a covered booking on a Day Office bundle also takes an office" do
    member, bundle, booking, room_a, = setup_office_booking

    result = nil
    assert_enqueued_with(job: SendNotificationsJob, args: ->(a) { a[1] == "DayOfficeAssigned" }) do
      result = Billing::Reservations::RedeemBundlePass.call(
        reservation: booking, user: member, use_bundle_pass: true)
    end

    assert_equal :redeemed, result.outcome
    assert_equal 4, bundle.reload.passes_remaining
    assert_equal room_a, result.office_hold.room
  end

  test "the minted pass keeps the member's booking in `reservation`; the hold is a DIFFERENT row" do
    member, _bundle, booking, = setup_office_booking

    result = Billing::Reservations::RedeemBundlePass.call(
      reservation: booking, user: member, use_bundle_pass: true)

    pass = result.bundle_redemption_day_pass
    hold = pass.reload_office_hold

    assert_equal booking.id, pass.reservation_id, "the covered booking linkage must not move"
    assert_not_equal booking.id, hold.id, "the office hold is its own reservation"
    assert_equal pass.id, hold.day_office_pass_id
    # And the booking itself was never repurposed as a hold.
    assert_nil booking.reload.day_office_pass_id
  end

  test "a full pool leaves the booking covered and office-less, and pages staff" do
    member, bundle, booking, room_a, room_b = setup_office_booking
    ActsAsTenant.with_tenant(@operator) { fill_office_pool!(@day, room_a, room_b) }

    result = Billing::Reservations::RedeemBundlePass.call(
      reservation: booking, user: member, use_bundle_pass: true)

    assert_equal :redeemed, result.outcome, "coverage must not depend on office availability"
    assert_equal 4, bundle.reload.passes_remaining
    assert_nil result.office_hold
    assert_nil result.bundle_redemption_day_pass.reload_office_hold

    # Booking variant, admin first — this burn can be days ahead of the date,
    # so nobody has "arrived" and neither message may say "today".
    assert_equal %w[DayOfficeUnassignedBookingAlert DayOfficeUnavailable], day_office_push_types
  end

  test "the office-less booking copy carries the booking's date, never 'today'" do
    member, _bundle, booking, room_a, room_b = setup_office_booking
    ActsAsTenant.with_tenant(@operator) { fill_office_pool!(@day, room_a, room_b) }

    result = Billing::Reservations::RedeemBundlePass.call(
      reservation: booking, user: member, use_bundle_pass: true)
    pass = result.bundle_redemption_day_pass
    short_date = @day.strftime("%b %-d")

    member_copy = NotifiableFactory.for(pass, "DayOfficeUnavailable").send(:message)
    assert_equal "No offices are left on #{short_date} — your pass still works; see staff.", member_copy
    assert_not_includes member_copy, "today"

    admin_copy = NotifiableFactory.for(pass, "DayOfficeUnassignedBookingAlert").send(:message)
    assert_equal "#{member.name} booked a Day Office for #{short_date} but no office was free — " \
                 "reassign a room or restore the pass", admin_copy
    assert_not_includes admin_copy, "arrived"
    assert_not_includes admin_copy, "today"
  end

  test "the assigned copy also carries the booking's date" do
    member, _bundle, booking, = setup_office_booking

    result = Billing::Reservations::RedeemBundlePass.call(
      reservation: booking, user: member, use_bundle_pass: true)

    copy = NotifiableFactory.for(result.bundle_redemption_day_pass, "DayOfficeAssigned").send(:message)
    assert_equal "🔑 Office A is yours on #{@day.strftime('%b %-d')}, #{result.office_hold.window_label}", copy
  end

  test "a standard bundle covers the booking with no office and no office notifications" do
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location, included_meeting_room_minutes: 60)
      bundle = DayPassBundle.create!(user: member, operator: @operator, location: @location,
                                     day_pass_type: type, quantity_purchased: 5, passes_remaining: 5,
                                     purchased_at: Time.current)
      room = create(:room, operator: @operator, location: @location,
                    hourly_rate_in_cents: 0, include_with_day_pass: true)
      booking = create(:reservation, user: member, room: room, minutes: 60,
                       datetime_in: @day.to_time + 9.hours)

      result = Billing::Reservations::RedeemBundlePass.call(
        reservation: booking, user: member, use_bundle_pass: true)

      assert_equal :redeemed, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
      assert_nil result.office_hold
      assert_nil result.bundle_redemption_day_pass.reload_office_hold
      assert_empty day_office_push_types
    end
  end
end
