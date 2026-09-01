require "test_helper"

class Billing::Reservations::CoverageStateTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def included_room
    create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
  end

  def dpt(minutes: 60, cents: 4000)
    create(:day_pass_type, operator: @operator, location: @location,
           included_meeting_room_minutes: minutes, amount_in_cents: cents, available: true, visible: true)
  end

  test "paid room is not_applicable" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 5000, include_with_day_pass: false)
      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 2, location: @location)
      assert_equal :not_applicable, state.outcome
    end
  end

  test "existing day pass for the date is already_covered" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      date = Date.current + 2
      create(:day_pass, user: user, billable: user, operator: @operator, location: @location, day_pass_type: dpt, day: date)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: date, location: @location)
      assert_equal :already_covered, state.outcome
    end
  end

  test "a cancelled-booking leftover pass is reusable, preferred over a bundle" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = included_room
      # a spare purchased pass from a cancelled booking, dated to another future day.
      # Link while ACTIVE, then cancel — acts_as_tenant can't validate a cancelled
      # (default-scoped) reservation association on save.
      spare_res = create(:reservation, user: user, room: room, minutes: 60)
      spare = create(:day_pass, user: user, billable: user, operator: @operator, location: @location,
                     day_pass_type: dpt, day: Date.current + 5, reservation: spare_res)
      spare_res.update!(cancelled: true)
      # also owns a bundle
      bt = dpt
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: bt,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)

      state = Billing::Reservations::CoverageState.for(user: user, room: room, date: Date.current + 3, location: @location)
      assert_equal :reusable_pass, state.outcome
      assert_equal spare.id, state.reusable_pass.id
    end
  end

  test "an active bundle (no spare) is bundle_available" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 3, purchased_at: Time.current)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :bundle_available, state.outcome
      assert_equal 3, state.passes_remaining
    end
  end

  # ADR 0018: a pass may not cover a date past its bundle's expiration — the
  # preview must not offer a bundle the booking path (RedeemBundlePass) refuses.
  test "a bundle expiring before the requested date is needs_purchase, not bundle_available" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 3, purchased_at: Time.current,
                            expires_at: 1.day.from_now.change(hour: 12))
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :needs_purchase, state.outcome
    end
  end

  test "a bundle expiring later today still covers a same-day booking" do
    travel_to Time.current.change(hour: 9) do
      ActsAsTenant.with_tenant(@operator) do
        user = create(:user, operator: @operator, original_location: @location, current_location: @location)
        DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: dpt,
                              quantity_purchased: 5, passes_remaining: 3, purchased_at: Time.current,
                              expires_at: Time.current.change(hour: 18))
        state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current, location: @location)
        assert_equal :bundle_available, state.outcome
      end
    end
  end

  test "only bundles surviving the requested date count: draws the survivor and sums only its passes" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bt = dpt
      DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: bt,
                            quantity_purchased: 5, passes_remaining: 3, purchased_at: Time.current,
                            expires_at: 1.day.from_now.change(hour: 12))
      survivor = DayPassBundle.create!(user: user, operator: @operator, location: @location, day_pass_type: bt,
                                       quantity_purchased: 5, passes_remaining: 2, purchased_at: Time.current)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :bundle_available, state.outcome
      assert_equal survivor.id, state.bundle.id
      assert_equal 2, state.passes_remaining
    end
  end

  test "no coverage is needs_purchase and carries the suggested type + price" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      t = dpt(cents: 4000)
      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :needs_purchase, state.outcome
      assert_equal t.id, state.day_pass_type.id
      assert_equal 4000, state.amount_cents
    end
  end

  # ADR 0026: office-backed types are excluded from the suggestion by KIND,
  # not by a %office% name-match — an office pass is never auto-suggested as
  # mere room coverage.
  test "office-backed types are excluded from the suggestion by kind, not by name" do
    ActsAsTenant.with_tenant(@operator) do
      user = create(:user, operator: @operator, original_location: @location, current_location: @location)
      # Cheapest, but kind: day_office — must never be suggested as room coverage,
      # regardless of its (office-free) name.
      create(:day_pass_type, operator: @operator, location: @location,
             name: "Private Suite", kind: "day_office", amount_in_cents: 500)
      # Named the way the old ILIKE would have wrongly excluded — must now be suggestible.
      office_named = create(:day_pass_type, operator: @operator, location: @location,
                            name: "Office Hours Pass", amount_in_cents: 3000)

      state = Billing::Reservations::CoverageState.for(user: user, room: included_room, date: Date.current + 3, location: @location)
      assert_equal :needs_purchase, state.outcome
      assert_equal office_named.id, state.day_pass_type.id
    end
  end
end
