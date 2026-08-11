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
#  reservation_id   :bigint(8)
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
#  index_day_passes_on_reservation_id                 (reservation_id)
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

class DayPassReservationLinkTest < ActiveSupport::TestCase
  test "a day pass optionally belongs to a reservation" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      loc  = locations(:cowork_tahoe_location)
      user = create(:user, operator: operator, original_location: loc, current_location: loc)
      dpt  = create(:day_pass_type, operator: operator, location: loc, included_meeting_room_minutes: 60)
      room = create(:room, operator: operator, location: loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60)
      dp   = create(:day_pass, user: user, billable: user, operator: operator, location: loc,
                    day_pass_type: dpt, day: Date.current, reservation: res)
      assert_equal res, dp.reload.reservation
    end
  end
end

class DayPassReusableCoverageScopeTest < ActiveSupport::TestCase
  test "a pass linked to a CANCELLED reservation is returned by reusable_coverage" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      loc  = locations(:cowork_tahoe_location)
      user = create(:user, operator: operator, original_location: loc, current_location: loc)
      dpt  = create(:day_pass_type, operator: operator, location: loc, included_meeting_room_minutes: 60)
      room = create(:room, operator: operator, location: loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60)
      dp   = create(:day_pass, user: user, billable: user, operator: operator, location: loc,
                    day_pass_type: dpt, day: Date.current + 5, reservation: res)
      res.update!(cancelled: true) # cancel AFTER linking — acts_as_tenant can't validate a cancelled (default-scoped) reservation on save

      assert DayPass.reusable_coverage(Date.current).exists?(id: dp.id)
    end
  end

  test "a pass linked to an ACTIVE reservation is NOT returned by reusable_coverage" do
    operator = operators(:cowork_tahoe)
    ActsAsTenant.with_tenant(operator) do
      loc  = locations(:cowork_tahoe_location)
      user = create(:user, operator: operator, original_location: loc, current_location: loc)
      dpt  = create(:day_pass_type, operator: operator, location: loc, included_meeting_room_minutes: 60)
      room = create(:room, operator: operator, location: loc, hourly_rate_in_cents: 0, include_with_day_pass: true)
      res  = create(:reservation, user: user, room: room, minutes: 60, cancelled: false)
      dp   = create(:day_pass, user: user, billable: user, operator: operator, location: loc,
                    day_pass_type: dpt, day: Date.current + 5, reservation: res)

      refute DayPass.reusable_coverage(Date.current).exists?(id: dp.id)
    end
  end
end

# ADR 0026: a Day Office pass's live hold is a has_one through the
# reservations.day_office_pass_id FK (Reservation's default_scope hides a
# cancelled hold automatically). Destroying the pass must release the hold
# through DayOffices::ReleaseHold — the single release authority for every
# destroy path (refund rescind, cancel-scheduled-day, console) — not just rely
# on the FK's ON DELETE SET NULL backstop, which would free the FK column but
# leave the reservation live and the room un-bookable.
class DayPassOfficeHoldTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500)
    @room = Room.create!(name: "Office A", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room.id => 1 })
    @user = users(:cowork_tahoe_member)
    @day = Date.current + 7
    @pass = DayPass.create!(user: @user, billable: @user, operator: @operator,
                            location: @location, day_pass_type: @office_type, day: @day, imported: true)
  end

  test "destroying a pass releases its office hold" do
    hold = DayOffices::Allocator.allocate!(day_pass: @pass)
    @pass.destroy!
    assert Reservation.unscoped.find(hold.id).cancelled
  end

  test "destroying a pass releases its hold even if office_hold was read (and cached nil) before allocation" do
    @pass.office_hold # arm the memoized nil — reads before any hold exists
    hold = DayOffices::Allocator.allocate!(day_pass: @pass)
    @pass.destroy!
    assert Reservation.unscoped.find(hold.id).cancelled, "before_destroy must reload, not trust the stale cached nil"
  end

  test "office_hold reflects only the live reservation, nil once released" do
    hold = DayOffices::Allocator.allocate!(day_pass: @pass)
    assert_equal hold, @pass.reload.office_hold

    DayOffices::ReleaseHold.call(hold)
    assert_nil @pass.reload.office_hold, "default_scope hides the now-cancelled reservation"
  end

  test "day_office? delegates to day_pass_type: true for office, false for standard, nil-safe with no type" do
    assert @pass.day_office?

    standard_type = DayPassType.create!(name: "Standard", operator: @operator, location: @location)
    standard_pass = DayPass.create!(user: @user, billable: @user, operator: @operator, location: @location,
                                    day_pass_type: standard_type, day: @day + 1, imported: true)
    refute standard_pass.day_office?

    assert_nil DayPass.new.day_office?
  end
end
