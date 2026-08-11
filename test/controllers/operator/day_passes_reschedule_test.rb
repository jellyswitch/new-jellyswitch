require "test_helper"

class Operator::DayPassesRescheduleTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: 2.days.from_now.to_date)
    @tz = ActiveSupport::TimeZone[@location.time_zone]

    # Day Office pool (Task 9 / ADR 0026) — mirrors Api::V1::DayPassesRescheduleTest.
    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })
  end

  # A purchased-and-allocated Day Office pass for the fixture member on `day`.
  def office_pass!(day)
    member = users(:cowork_tahoe_member)
    pass = DayPass.create!(user: member, billable: member, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: day, imported: true)
    DayOffices::Allocator.allocate!(day_pass: pass)
    pass
  end

  test "admin moves a member's unused pass" do
    log_in users(:cowork_tahoe_admin)
    target = 7.days.from_now.to_date

    patch reschedule_day_pass_path(@pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(@pass.user)
    assert_equal target, @pass.reload.day
  end

  test "a staff move emails the member a confirmation" do
    log_in users(:cowork_tahoe_admin)
    original = @pass.day
    target = 7.days.from_now.to_date

    assert_enqueued_email_with UserMailer, :day_pass_rescheduled, args: [@pass.id, original] do
      patch reschedule_day_pass_path(@pass), params: { day: target.iso8601 }, env: default_env
    end
    assert_equal target, @pass.reload.day
  end

  test "a rejected staff move sends no email" do
    log_in users(:cowork_tahoe_admin)

    assert_no_enqueued_emails do
      patch reschedule_day_pass_path(@pass), params: { day: 2.days.ago.to_date.iso8601 }, env: default_env
    end
  end

  test "member cannot use the staff reschedule endpoint" do
    log_in users(:cowork_tahoe_member)
    original = @pass.day

    patch reschedule_day_pass_path(@pass), params: { day: 7.days.from_now.to_date.iso8601 }, env: default_env

    assert_response :redirect
    assert_equal original, @pass.reload.day
  end

  test "a used pass is not moved" do
    log_in users(:cowork_tahoe_admin)
    d = @pass.day
    Checkin.create!(user: @pass.user, billable: @pass.user, location: @location,
                    datetime_in: @tz.local(d.year, d.month, d.day, 10, 0))

    patch reschedule_day_pass_path(@pass), params: { day: 9.days.from_now.to_date.iso8601 }, env: default_env

    assert_equal d, @pass.reload.day
    assert_match "already used", flash[:error]
  end

  test "a past date is rejected" do
    log_in users(:cowork_tahoe_admin)
    original = @pass.day

    patch reschedule_day_pass_path(@pass), params: { day: 2.days.ago.to_date.iso8601 }, env: default_env

    assert_equal original, @pass.reload.day
    assert_match "future date", flash[:error]
  end

  # --- Day Office: reschedule moves the hold (Task 9 / ADR 0026) -----------

  test "an office pass reschedule moves its hold to the new date" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    target = 7.days.from_now.to_date

    patch reschedule_day_pass_path(pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(pass.user)
    assert_equal target, pass.reload.day
    hold = pass.reload_office_hold
    assert_equal target, hold.datetime_in.to_date
    assert_match "moved", flash[:success]
  end

  test "an office pass reschedule to a full target date flashes an error and changes nothing" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    original_day = pass.day
    original_hold_id = pass.office_hold.id
    target = 7.days.from_now.to_date
    span = @location.posted_hours_span(target)
    other = users(:cowork_tahoe_non_member)
    [@room_a, @room_b].each { |r| Reservation.create!(user: other, room: r, datetime_in: span.first, minutes: 600) }

    patch reschedule_day_pass_path(pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(pass.user)
    assert_equal original_day, pass.reload.day
    assert_equal original_hold_id, pass.reload_office_hold&.id
    assert_match "fully booked", flash[:error]
  end

  # --- Day Office: profile reassign surface (Task 14, ADR 0026) ------------

  test "profile shows the office room, window, and a reassign select with a free room option" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    hold = pass.office_hold
    assert_equal @room_a, hold.room # sanity: allocator fills @room_a first

    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    assert_match @room_a.name, response.body
    assert_match hold.window_label, response.body
    assert_select "form[action=?]", reassign_room_reservation_path(hold) do
      assert_select "select[name=?]", "room_id" do
        assert_select "option[value=?]", @room_b.id.to_s
      end
    end
  end

  # Room's own acts_as_scopable(:operator, :location) default scope — set for
  # the whole request by Operator::BaseController#set_resource_scopes — must
  # not silently AND the admin's OWN current_location into options_for's
  # candidate query. Without Room.unscoped there, a hold at a DIFFERENT
  # location than current_location would show zero options no matter what's
  # actually free there.
  test "profile's reassign select still offers a free room when the hold is at a different location than current_location" do
    other_location = create(:location, operator: @operator, name: "Satellite Office")
    office_type = DayPassType.create!(name: "Satellite Office Pass", operator: @operator, location: other_location,
                                      kind: "day_office", amount_in_cents: 7500,
                                      included_meeting_room_minutes: 0, available: true, visible: true)
    room_a = Room.create!(name: "Satellite A", operator: @operator, location: other_location)
    room_b = Room.create!(name: "Satellite B", operator: @operator, location: other_location)
    office_type.assign_office_rooms!({ room_a.id => 1, room_b.id => 2 })
    member = users(:cowork_tahoe_member)
    pass = DayPass.create!(user: member, billable: member, operator: @operator, location: other_location,
                           day_pass_type: office_type, day: 2.days.from_now.to_date, imported: true)
    hold = DayOffices::Allocator.allocate!(day_pass: pass)
    assert_equal room_a, hold.room # sanity: allocator picked the position-1 room

    log_in users(:cowork_tahoe_admin) # current_location resolves to @location, NOT other_location
    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    refute_match "No other rooms free", response.body
    assert_select "select[name=?]", "room_id" do
      assert_select "option[value=?]", room_b.id.to_s
    end
  end

  test "a hidden current room is noted, and a hidden free room is still offered in the select" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    hold = pass.office_hold
    @room_a.update!(visible: false)
    @room_b.update!(visible: false)

    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    assert_match "(hidden)", response.body
    assert_select "select[name=?]", "room_id" do
      assert_select "option[value=?]", @room_b.id.to_s, text: /#{Regexp.escape(@room_b.name)} \(hidden\)/
    end
  end

  test "a past-window hold still shows the office info line but hides the reassign select" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    hold = pass.office_hold
    hold.update_columns(datetime_in: 2.days.ago, minutes: 60) # ended well before now
    assert hold.datetime_out <= Time.current, "sanity: window is in the past"

    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    assert_match @room_a.name, response.body # info line still renders
    assert_select "select[name=?]", "room_id", false
    assert_select "form[action=?]", reassign_room_reservation_path(hold), false
  end

  test "an empty options list renders 'No other rooms free' instead of a select" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    hold = pass.office_hold
    # Remove every other active room at the location so
    # DayOffices::ReassignRoom.options_for(hold) has nothing left to offer.
    @room_b.update!(archived: true)
    rooms(:small_meeting_room).update!(archived: true)
    rooms(:large_meeting_room).update!(archived: true)

    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    assert_match "No other rooms free", response.body
    assert_select "select[name=?]", "room_id", false
  end

  test "a non-staff member does not see the reassign select" do
    log_in users(:cowork_tahoe_admin) # only staff can even reach the profile page (UserPolicy#admin_day_passes?)
    pass = office_pass!(2.days.from_now.to_date)
    hold = pass.office_hold
    DayPassPolicy.any_instance.stubs(:reschedule?).returns(false)

    get user_admin_day_passes_path(pass.user), env: default_env

    assert_response :success
    assert_select "select[name=?]", "room_id", false
    assert_select "form[action=?]", reassign_room_reservation_path(hold), false
  end
end
