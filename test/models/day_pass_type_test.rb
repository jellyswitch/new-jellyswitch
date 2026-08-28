# == Schema Information
#
# Table name: day_pass_types
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(FALSE), not null
#  amount_in_cents               :integer          default(0), not null
#  available                     :boolean          default(TRUE), not null
#  code                          :string
#  default_for_room_booking      :boolean          default(FALSE), not null
#  included_meeting_room_minutes :integer
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0), not null
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          not null
#
# Indexes
#
#  index_day_pass_types_on_location_id  (location_id)
#  index_dpt_on_op_loc_default          (operator_id,location_id,default_for_room_booking)
#
require "test_helper"

class DayPassTypeTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_member)
  end

  test "DayPassType.all_options_for_select returns all available day pass types for user with billing" do
    @user.stub(:has_billing_for_location?, true) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available
    end
  end

  test "DayPassType.all_options_for_select returns only free day pass types for user without billing" do
    @user.stub(:has_billing_for_location?, false) do
      day_pass_types = DayPassType.all_options_for_select(@location, @user)

      assert_equal day_pass_types, DayPassType.where(location_id: @location.id).available.free
    end
  end

  # --- daily_limit (per-day sales cap) ---

  test "daily_limit must be a positive integer when present" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.daily_limit = 0
    assert_not dpt.valid?
    dpt.daily_limit = 2
    assert dpt.valid?
    dpt.daily_limit = nil
    assert dpt.valid?, "nil daily_limit means unlimited and must be valid"
  end

  test "daily_limit_reached? is always false when no limit is set" do
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    assert_nil dpt.daily_limit
    assert_not dpt.daily_limit_reached?(day: Date.current, location: @location)
  end

  test "daily_limit_reached? counts every pass of the type on that day at that location" do
    operator = operators(:cowork_tahoe)
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    dpt.update!(daily_limit: 2)
    day = Date.current + 3

    ActsAsTenant.with_tenant(operator) do
      # 1st pass: a normal purchased pass
      DayPass.create!(user: @user, billable: @user, operator: operator,
                      location: @location, day_pass_type: dpt, day: day, imported: true)
      assert_not dpt.daily_limit_reached?(day: day, location: @location),
                 "1 of 2 is under the limit"

      # 2nd pass: complimentary — still counts (limit models physical capacity)
      other = users(:cowork_tahoe_non_member)
      DayPass.create!(user: other, billable: other, operator: operator,
                      location: @location, day_pass_type: dpt, day: day,
                      complimentary: true, imported: true)
      assert dpt.daily_limit_reached?(day: day, location: @location),
             "2 of 2 reaches the limit; complimentary passes count"

      # Different day and different location are unaffected
      assert_not dpt.daily_limit_reached?(day: day + 1, location: @location)
      other_location = Location.where.not(id: @location.id).first ||
        Location.create!(operator: operator, name: "Other Location")
      assert_not dpt.daily_limit_reached?(day: day, location: other_location)
    end
  end

  # --- kind / office room pool (ADR 0026) ---

  test "kind defaults to standard and day_office requires a location" do
    t = DayPassType.new(name: "X", operator: operators(:cowork_tahoe), amount_in_cents: 100)
    assert t.standard?
    t.kind = "day_office"
    assert_not t.valid?
    assert t.errors[:location].present?
    t.location = locations(:cowork_tahoe_location)
    assert t.valid?
  end

  # Lenient-nil convention (house-wide, see memory): a standard type is the
  # legacy/default shape and must stay valid with no location, unlike a
  # day_office type.
  test "standard kind with no location stays valid" do
    t = DayPassType.new(name: "X", operator: operators(:cowork_tahoe), amount_in_cents: 100)
    assert_nil t.location
    assert t.valid?
  end

  test "assign_office_rooms! replaces the pool in priority order" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:cowork_tahoe),
                               location: locations(:cowork_tahoe_location), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    b = Room.create!(name: "B", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    type.assign_office_rooms!({ b.id => 1, a.id => 2 })
    assert_equal [b.id, a.id], type.office_rooms.map(&:id)
    type.assign_office_rooms!({ a.id => 1 })
    assert_equal [a.id], type.office_rooms.map(&:id)
  end

  test "assign_office_rooms! with an empty hash clears the pool" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:cowork_tahoe),
                               location: locations(:cowork_tahoe_location), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    type.assign_office_rooms!({ a.id => 1 })
    assert_equal [a.id], type.office_rooms.map(&:id)

    type.assign_office_rooms!({})
    assert_empty type.office_rooms
  end

  test "assign_office_rooms! is atomic: a cross-location room raises and leaves the pool unchanged" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:cowork_tahoe),
                               location: locations(:cowork_tahoe_location), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    type.assign_office_rooms!({ a.id => 1 })

    other_location = Location.create!(operator: operators(:cowork_tahoe), name: "Other Location")
    stray = Room.create!(name: "Stray", operator: operators(:cowork_tahoe), location: other_location)

    assert_raises(ActiveRecord::RecordInvalid) do
      type.assign_office_rooms!({ a.id => 2, stray.id => 1 })
    end

    # No reload: this must hold from the association's own (reset) cache,
    # not merely from a fresh query.
    assert_equal [a.id], type.office_rooms.map(&:id)
    assert_equal 1, DayPassTypeRoom.find_by(day_pass_type: type, room: a).position

    # Regression pin: the failed assign used to leave a phantom invalid
    # DayPassTypeRoom sitting in the loaded association target (built via
    # find_or_initialize_by, never removed by a DB rollback). The has_many
    # autosave-validation callback then re-validates that phantom on ANY
    # later save of `type` — even one with nothing to do with the pool.
    type.update!(name: "Renamed")
    assert_equal "Renamed", type.reload.name
  end

  test "assign_office_rooms! ignores blank keys" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:cowork_tahoe),
                               location: locations(:cowork_tahoe_location), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    type.assign_office_rooms!({ "" => "1", a.id => "2" })
    assert_equal [a.id], type.office_rooms.map(&:id)
  end

  test "assign_office_rooms! breaks equal positions by id" do
    type = DayPassType.create!(name: "Day Office", operator: operators(:cowork_tahoe),
                               location: locations(:cowork_tahoe_location), kind: "day_office", amount_in_cents: 7500)
    a = Room.create!(name: "A", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    b = Room.create!(name: "B", operator: operators(:cowork_tahoe), location: locations(:cowork_tahoe_location))
    type.assign_office_rooms!({ a.id => 1, b.id => 1 })
    lower, higher = [a.id, b.id].sort
    assert_equal [lower, higher], type.office_rooms.map(&:id)
  end

  test "an invalid kind value fails validation instead of raising" do
    t = DayPassType.new(name: "X", operator: operators(:cowork_tahoe), amount_in_cents: 100)
    t.kind = "office"
    assert_not t.valid?
    assert t.errors[:kind].present?
  end

  # --- day_office capacity + suggestion fallback (ADR 0026, decisions #6/#7) ---

  test "daily_limit_reached? for day_office types is room availability, ignoring daily_limit" do
    operator = operators(:cowork_tahoe)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    type = DayPassType.create!(name: "Day Office", operator: operator, location: @location,
                               kind: "day_office", amount_in_cents: 7500, daily_limit: 99)
    a = Room.create!(name: "A", operator: operator, location: @location)
    b = Room.create!(name: "B", operator: operator, location: @location)
    type.assign_office_rooms!({ a.id => 1, b.id => 2 })
    day = Date.current + 7

    assert_not type.daily_limit_reached?(day: day, location: @location),
               "both pool rooms are free; a daily_limit of 99 must not matter either way"

    span = @location.posted_hours_span(day)
    [a, b].each { |r| Reservation.create!(user: users(:cowork_tahoe_non_member), room: r, datetime_in: span.first, minutes: 600) }
    assert type.daily_limit_reached?(day: day, location: @location),
           "both pool rooms are now taken; sold out even though daily_limit (99) is nowhere near reached"
  end

  test "day_office type with empty pool is always sold out" do
    operator = operators(:cowork_tahoe)
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    type = DayPassType.create!(name: "Day Office", operator: operator, location: @location,
                               kind: "day_office", amount_in_cents: 7500)
    assert_nil type.daily_limit, "unset daily_limit must not short-circuit the day_office branch to false"
    assert_empty type.office_rooms
    assert type.daily_limit_reached?(day: Date.current + 7, location: @location)
  end

  test "suggested_standard_for prefers default_for_room_booking, else cheapest paid standard, never day_office" do
    operator = operators(:cowork_tahoe)
    std = DayPassType.create!(name: "Regular", operator: operator, location: @location,
                              amount_in_cents: 4000, default_for_room_booking: true)
    assert_equal std, DayPassType.suggested_standard_for(@location)

    std.update!(default_for_room_booking: false)
    cheaper = DayPassType.create!(name: "Cheap", operator: operator, location: @location, amount_in_cents: 2000)
    assert_equal cheaper, DayPassType.suggested_standard_for(@location)

    # An office-NAMED standard type must now be suggestible — name no longer matters.
    office_named = DayPassType.create!(name: "Office Pass", operator: operator, location: @location, amount_in_cents: 1000)
    assert_equal office_named, DayPassType.suggested_standard_for(@location)

    # A day_office-KIND type must never be suggested, even as the cheapest candidate.
    DayPassType.create!(name: "Actual Office", operator: operator, location: @location,
                        kind: "day_office", amount_in_cents: 100)
    assert_equal office_named, DayPassType.suggested_standard_for(@location)
  end

  test "suggested_standard_for returns nil when location is nil" do
    assert_nil DayPassType.suggested_standard_for(nil)
  end

  test "suggested_standard_for never suggests free, invisible, unavailable, or other-operator types" do
    operator = operators(:cowork_tahoe)
    other_operator = Operator.create!(name: "Other Operator", subdomain: "other-operator-test")

    # Each is cheaper than the one eligible type below, so if any filter were
    # dropped, that filter's type — not the eligible one — would win on price.
    DayPassType.create!(name: "Free", operator: operator, location: @location, amount_in_cents: 0)
    DayPassType.create!(name: "Invisible", operator: operator, location: @location,
                        amount_in_cents: 100, visible: false)
    DayPassType.create!(name: "Unavailable", operator: operator, location: @location,
                        amount_in_cents: 100, available: false)
    DayPassType.create!(name: "Other Operator's Pass", operator: other_operator, amount_in_cents: 100)

    eligible = DayPassType.create!(name: "Eligible", operator: operator, location: @location, amount_in_cents: 5000)
    assert_equal eligible, DayPassType.suggested_standard_for(@location)
  end

  test "suggested_standard_for prefers a location-specific default over a nil-location operator-wide default" do
    operator = operators(:cowork_tahoe)
    # Cheaper, but location: nil (operator-wide) — must lose to the pricier, location-specific default.
    DayPassType.create!(name: "Global Default", operator: operator, location: nil,
                        amount_in_cents: 1000, default_for_room_booking: true)
    local_default = DayPassType.create!(name: "Local Default", operator: operator, location: @location,
                                        amount_in_cents: 9000, default_for_room_booking: true)
    assert_equal local_default, DayPassType.suggested_standard_for(@location)
  end

  test "suggested_standard_for never suggests a bundle (quantity > 1)" do
    operator = operators(:cowork_tahoe)
    # Neutralize the operator's fixture standard type (day_pass_type.yml,
    # $200/quantity 1) — it would otherwise qualify on its own and mask the
    # thing this test checks.
    day_pass_type(:cowork_tahoe_day_pass_type).update!(available: false)
    DayPassType.create!(name: "10-Pack", operator: operator, location: @location,
                        amount_in_cents: 20000, quantity: 10)
    assert_nil DayPassType.suggested_standard_for(@location),
               "the only qualifying type is an N-Pack — posting its id back would route into the bundle-buy flow, not a same-day swap"
  end

  test "suggested_standard_for prefers a quantity-1 type over a cheaper bundle" do
    operator = operators(:cowork_tahoe)
    DayPassType.create!(name: "Cheap 10-Pack", operator: operator, location: @location,
                        amount_in_cents: 1000, quantity: 10)
    single = DayPassType.create!(name: "Single", operator: operator, location: @location,
                                 amount_in_cents: 5000, quantity: 1)
    assert_equal single, DayPassType.suggested_standard_for(@location)
  end
  # Pack-name/quantity guard (TLH 2026-08-10, Fulton 2026-08-27 mis-sells).
  test "an N-pack name with a mismatched quantity is invalid" do
    t = DayPassType.new(name: "2 day pass pack", quantity: 1, amount_in_cents: 5900,
                        operator: operators(:cowork_tahoe))
    refute t.valid?
    assert_match(/name says 2-pack/, t.errors[:quantity].join)
  end

  test "an N-pack name with the matching quantity is valid on that rule" do
    t = DayPassType.new(name: "5-Day Pack", quantity: 5, amount_in_cents: 15000,
                        operator: operators(:cowork_tahoe))
    t.valid?
    assert_empty t.errors[:quantity]
  end

  test "non-pack names are not guarded" do
    t = DayPassType.new(name: "Coworking Day Pass", quantity: 1, amount_in_cents: 4000,
                        operator: operators(:cowork_tahoe))
    t.valid?
    assert_empty t.errors[:quantity]
  end

end
