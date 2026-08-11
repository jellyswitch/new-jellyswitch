# Shared Day Office bundle fixtures for tests (Task 10 / ADR 0026). Mirrors
# the DayPassType(kind: "day_office") + 2-room pool + DayPassBundle idiom that
# used to be copy-pasted across Billing::DayPassBundles::ScheduleDayTest,
# Billing::DayPassBundles::CancelScheduledDayTest, Api::V1::DayPassesSchedulingTest,
# and Api::V1::DayPassesRedeemTodayTest.
module DayOfficeHelper
  # Creates a Day Office DayPassType with a 2-room pool + an active bundle.
  # Reads @operator/@location ambiently (the suite's existing bundle-fixture
  # idiom — see StripeHelper). `member:` defaults to @member but can be
  # overridden when a test needs a dedicated member (e.g. to avoid colliding
  # with another bundle already on @member from the surrounding setup).
  # Returns [bundle, room_a, room_b].
  def make_office_bundle(member: @member, qty: 5, remaining: qty)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Office #{qty}-Pack",
                              amount_in_cents: 20000, quantity: qty, kind: "day_office",
                              included_meeting_room_minutes: 0, available: true, visible: true)
    room_a = Room.create!(name: "Office A", operator: @operator, location: @location)
    room_b = Room.create!(name: "Office B", operator: @operator, location: @location)
    dpt.assign_office_rooms!({ room_a.id => 1, room_b.id => 2 })
    bundle = DayPassBundle.create!(user: member, operator: @operator, location: @location, day_pass_type: dpt,
                                   quantity_purchased: qty, passes_remaining: remaining, purchased_at: Time.current)
    [bundle, room_a, room_b]
  end

  # Books both pool rooms solid for the whole posted-hours span on `day`, so
  # DayOffices::Allocator has nothing free to hand out. Mirrors
  # Billing::DayPasses::AllocateDayOfficeTest#fill_pool!. Caller must already
  # be inside an ActsAsTenant.with_tenant(@operator) block, same as
  # make_office_bundle's own callers (it creates a throwaway user via the
  # :user factory).
  def fill_office_pool!(day, room_a, room_b)
    span = @location.posted_hours_span(day)
    minutes = ((span.last - span.first) / 60).round
    other = create(:user, operator: @operator, original_location: @location, current_location: @location)
    [room_a, room_b].each do |room|
      Reservation.create!(user: other, room: room, datetime_in: span.first, minutes: minutes)
    end
  end
end
