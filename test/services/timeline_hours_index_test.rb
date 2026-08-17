require "test_helper"

# Day-pass and bundle timeline cards report the room hours booked against them.
# That total can't live in the activity payload — it accrues after the pass is
# bought — so the index resolves it at read time for a whole page at once.
class TimelineHoursIndexTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @room     = rooms(:small_meeting_room)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type   = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                    amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    end
  end

  def location_zone
    ActiveSupport::TimeZone[@location.time_zone.presence || "UTC"]
  end

  def book(local_time, minutes)
    Reservation.create!(user: @member, room: @room, datetime_in: local_time,
                        hours: minutes / 60.0, minutes: minutes)
  end

  def day_pass_activity_for(day)
    ActsAsTenant.with_tenant(@operator) do
      DayPass.create!(user: @member, operator: @operator, location: @location,
                      day_pass_type: @type, billable: @member, day: day)
    end
    Activity.where(user: @member, kind: "day_pass").order(:id).last
  end

  test "sums a day's room minutes for a day pass card" do
    day = location_zone.today - 3.days
    ActsAsTenant.with_tenant(@operator) do
      book(location_zone.parse("#{day} 09:00"), 60)
      book(location_zone.parse("#{day} 13:00"), 90)
      book(location_zone.parse("#{day - 1.day} 09:00"), 240) # another day — must not count
    end

    activity = day_pass_activity_for(day)
    index = TimelineHoursIndex.build(user: @member, activities: [activity])

    assert_equal 150, index.minutes_on(day)
  end

  test "excludes cancelled reservations from the day total" do
    day = location_zone.today - 4.days
    reservation = nil
    ActsAsTenant.with_tenant(@operator) do
      book(location_zone.parse("#{day} 09:00"), 60)
      reservation = book(location_zone.parse("#{day} 13:00"), 120)
    end
    reservation.update!(cancelled: true)

    index = TimelineHoursIndex.build(user: @member, activities: [day_pass_activity_for(day)])

    assert_equal 60, index.minutes_on(day)
  end

  # Late-evening local bookings sit on the NEXT UTC date. Bucketing by the room's
  # own zone is what keeps them on the day the member actually used the pass.
  test "buckets a late-evening booking on its local day, not the UTC day" do
    day = location_zone.today - 5.days
    ActsAsTenant.with_tenant(@operator) do
      book(location_zone.parse("#{day} 22:00"), 60)
    end

    index = TimelineHoursIndex.build(user: @member, activities: [day_pass_activity_for(day)])

    assert_equal 60, index.minutes_on(day)
    assert_equal 0, index.minutes_on(day + 1.day)
  end

  test "rolls a bundle up to passes used and hours booked across its burned days" do
    first_day  = location_zone.today - 7.days
    second_day = location_zone.today - 6.days

    bundle = nil
    ActsAsTenant.with_tenant(@operator) do
      bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                     day_pass_type: @type, quantity_purchased: 5, passes_remaining: 5,
                                     purchased_at: Time.current)
      [first_day, second_day].each do |day|
        pass = DayPass.create!(user: @member, operator: @operator, location: @location,
                               day_pass_type: @type, billable: @member, day: day)
        bundle.burn!(kind: "entry", performed_by: @member, day_pass: pass)
      end
      book(location_zone.parse("#{first_day} 09:00"), 60)
      book(location_zone.parse("#{second_day} 09:00"), 30)
    end

    activity = Activity.find_by!(kind: "day_pass_bundle", subject_type: "DayPassBundle", subject_id: bundle.id)
    summary = TimelineHoursIndex.build(user: @member, activities: [activity]).bundle(bundle.id)

    assert_equal 5, summary[:quantity]
    assert_equal 2, summary[:used]
    assert_equal 90, summary[:minutes]
  end

  test "guest burns carry no room time and do not inflate the bundle total" do
    bundle = nil
    ActsAsTenant.with_tenant(@operator) do
      bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                     day_pass_type: @type, quantity_purchased: 5, passes_remaining: 5,
                                     purchased_at: Time.current)
      bundle.burn!(kind: "guest", performed_by: @member, guest_name: "Visitor")
    end

    activity = Activity.find_by!(kind: "day_pass_bundle", subject_type: "DayPassBundle", subject_id: bundle.id)
    summary = TimelineHoursIndex.build(user: @member, activities: [activity]).bundle(bundle.id)

    assert_equal 1, summary[:used]
    assert_equal 0, summary[:minutes]
  end

  test "queries nothing when the page holds no day pass or bundle cards" do
    reservation_activity = nil
    ActsAsTenant.with_tenant(@operator) do
      reservation_activity = Activity.where(subject: book(location_zone.parse("#{location_zone.today} 09:00"), 60)).first
    end

    assert_no_queries do
      index = TimelineHoursIndex.build(user: @member, activities: [reservation_activity])
      assert_equal 0, index.minutes_on(location_zone.today)
    end
  end
end
