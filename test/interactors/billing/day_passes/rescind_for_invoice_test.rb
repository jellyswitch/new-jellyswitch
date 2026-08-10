require "test_helper"

# Regression pin for the Day Office cascade through the refund/rescind path
# (Task 12, ADR 0026). Billing::DayPasses::RescindForInvoice's own "skip a
# pass that still backs an ACTIVE reservation" guard reads `day_pass.reservation`
# — the ADR 0019 booking-COVERAGE link (day_passes.reservation_id). An office
# pass's hold lives on the other side of a DIFFERENT foreign key entirely
# (reservations.day_office_pass_id / day_pass.office_hold) and never touches
# reservation_id (already pinned in Billing::DayPasses::AllocateDayOfficeTest
# — "day_passes.reservation_id stays nil on an allocated office pass"). So a
# refunded office pass must never be mistaken for one backing a live booking:
# it gets destroyed like any other refunded pass, and DayPass#before_destroy's
# reload_office_hold callback releases the hold in the same stroke — that's
# the release authority (app/services/day_offices/release_hold.rb), not this
# interactor.
#
# The wider RescindForInvoice contract (past-pass carve-out, other-invoice
# isolation, the ADR 0019 booking-coverage skip itself) is already covered by
# spec/interactors/billing/day_passes/rescind_for_invoice_spec.rb; this file
# adds only the Day Office cascade that spec predates.
class Billing::DayPasses::RescindForInvoiceTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")

    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })

    @user    = users(:cowork_tahoe_member)
    @day     = Date.current + 7
    @invoice = create(:invoice, operator: @operator, location: @location, billable: @user)
  end

  test "refunding an office pass's invoice destroys the pass AND releases its hold — the skip guard reads the coverage link, not the hold" do
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: @day, invoice: @invoice, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    assert hold.present?, "sanity: allocation must have succeeded"

    # The mechanism under test: a guard that mistakenly read office_hold
    # instead of the coverage `reservation` would treat every office pass as
    # "backing a live reservation" and never rescind a single one.
    assert_nil pass.reservation, "sanity: an office hold must not satisfy the booking-coverage association"
    assert pass.office_hold.present?, "sanity: the hold link is the OTHER association"

    Billing::DayPasses::RescindForInvoice.call(invoice: @invoice)

    assert_not DayPass.exists?(pass.id), "the refunded pass must be destroyed"
    assert Reservation.unscoped.find(hold.id).cancelled,
      "the hold must be released (via DayPass#before_destroy), not left dangling and blocking the room"
  end

  test "refunding an office pass that never got a hold (walk-in sold-out) destroys cleanly" do
    # Task 11's fallback: the pass row can exist with no office_hold at all
    # when the pool was full at burn time. reload_office_hold must tolerate
    # nil without raising.
    pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: @day, invoice: @invoice, imported: true)
    assert_nil pass.office_hold, "sanity: no allocation happened"

    assert_nothing_raised do
      Billing::DayPasses::RescindForInvoice.call(invoice: @invoice)
    end

    assert_not DayPass.exists?(pass.id)
  end
end
