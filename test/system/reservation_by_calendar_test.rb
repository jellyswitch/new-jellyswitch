require "application_system_test_case"

class ReservationByCalendarTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:small_meeting_room)
    @day = Time.now

    @time = "10:00"

    @duration = "1.5 hours"
    @duration_minutes = 90

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    location.update(credits_enabled: false)

    Stripe::Invoice.any_instance.stubs(:number).returns("123456")
  end

  test "users go through the reserve by calendar flow and create reservation successfully" do
    StripeMock.start

    @user = users(:cowork_tahoe_member)
    sleep 1
    log_in @user

    setup_stripe

    click_on "Reserve Later"

    assert_text "Reservation Date"

    find(".fc-day-top[data-date='#{@day.strftime("%Y-%m-%d")}']").click

    assert_text "Reservation Details"
    assert_text @day.strftime("%B %-d, %Y")

    find(".form-check-label", text: "Night (PM)").click
    find(".time-slot", text: @time).click

    assert_text "Meeting Duration"
    find(".duration-slot", text: @duration).click

    assert_text "Available Room"

    select @room.name, from: "room_id"

    assert_text "Additional Amenities"

    find(".amenity-item", text: "AV - $25.5").click
    assert_equal "$25.50", find(".price-value").text

    click_on "Confirm"
    wait_for_ajax

    assert_text("Reservation Details")
    assert_link(@room.name, href: room_path(@room))
    assert_link(@user.name, href: user_path(@user))

    assert_text("#{@day.strftime("%m/%d/%Y")} at #{@time}pm")
    assert_text("#{@duration_minutes} minutes")
    assert_text("Amenities: AV")
  end

  test "non-membership users reserve paid meeting room" do
    StripeMock.start
    @room.update hourly_rate_in_cents: 1000
    @user = users(:cowork_tahoe_non_member)

    sleep 1
    log_in @user

    click_on "Book a meeting room"

    assert_text "Reservation Date"

    find(".fc-day-top[data-date='#{@day.strftime("%Y-%m-%d")}']").click
    find(".time-slot", text: @time).click
    find(".duration-slot", text: @duration).click
    select @room.name, from: "room_id"

    within ".amenities-list" do
      assert_text("AV - $50")
      assert_text("Coffee - $10.5")
    end

    click_on "Confirm"

    assert_text("Reservation Details")
    assert_text("Payment Required: Yes")
  end

  test "membership users reserve paid meeting room for free" do
    StripeMock.start
    @room.update hourly_rate_in_cents: 1000
    @user = users(:cowork_tahoe_member)
    setup_stripe

    log_in @user

    click_on "Reserve Now"
    wait_for_turbo

    assert_text "Reservation Date"

    find(".duration-slot", text: @duration).click
    select @room.name, from: "room_id"

    click_on "Confirm"
    wait_for_turbo

    assert_text("Reservation Details")
    assert_text("Payment Required: No")
  end

  test "membership users reserve free meeting room" do
    StripeMock.start
    @room.update hourly_rate_in_cents: 0
    @user = users(:cowork_tahoe_member)
    setup_stripe

    log_in @user

    click_on "Reserve Now"
    wait_for_turbo

    assert_text "Reservation Date"

    find(".duration-slot", text: @duration).click
    select @room.name, from: "room_id"

    click_on "Confirm"
    wait_for_turbo

    assert_text("Reservation Details")
    assert_text("Payment Required: No")
  end

  test "admin reserve paid meeting room for free but pay for amenities" do
    StripeMock.start
    @room.update hourly_rate_in_cents: 1000
    @user = users(:cowork_tahoe_admin)

    log_in @user
    sleep 1

    visit calendar_reservations_path(reserve_now: true)
    assert_text "Reservation Date"

    find(".duration-slot", text: @duration).click
    select @room.name, from: "room_id"

    within ".amenities-list" do
      assert_text("AV - $25.5")
      assert_text("Coffee - $0")
    end

    find(".amenity-item", text: "AV - $25.5").click
    assert_equal "$25.50", find(".price-value").text

    click_on "Confirm"

    assert_text("Reservation Details")
    assert_text("Payment Required: No")
  end

  test "calendar shows correct reservation counts and responds to room filter" do
    StripeMock.start
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)
    @other_room = rooms(:large_meeting_room)

    # remove all previous reservations
    Reservation.destroy_all

    # Create multiple reservations on same and different days
    create(:reservation, :morning, room: @room, user: @user)
    create(:reservation, :afternoon, room: @room, user: @user)
    create(:reservation, :evening, room: @other_room, user: @user)
    create(:reservation, :next_day, room: @other_room, user: @user)

    log_in @user
    visit calendar_reservations_path

    # Verify all reservations show up initially

    assert_text_for_date(Time.current.strftime("%Y-%m-%d"), "3 reservations")

    assert_text_for_date(Time.current.tomorrow.strftime("%Y-%m-%d"), "1 reservation")

    # Filter by first room
    select @room.name, from: "room-filter"

    # Verify filtered counts
    assert_text_for_date(Time.current.strftime("%Y-%m-%d"), "2 reservations")

    assert_no_text_for_date(Time.current.tomorrow.strftime("%Y-%m-%d"))

    # Filter by second room
    select @other_room.name, from: "room-filter"

    # Verify filtered counts again
    assert_text_for_date(Time.current.strftime("%Y-%m-%d"), "1 reservation")

    assert_text_for_date(Time.current.tomorrow.strftime("%Y-%m-%d"), "1 reservation")

    # Verify filter persists through month navigation
    find(".fc-next-button").click
    find(".fc-prev-button").click

    assert_text_for_date(Time.current.strftime("%Y-%m-%d"), "1 reservation")
  end

  test "modal shows chronologically ordered reservation details in collapsible view" do
    StripeMock.start
    @user = users(:cowork_tahoe_member)
    @room = rooms(:small_meeting_room)
    @other_room = rooms(:large_meeting_room)

    # remove all previous reservations
    Reservation.destroy_all

    # Create reservations in non-chronological order to ensure sorting works
    evening = create(:reservation, :evening, room: @room, user: @user)
    morning = create(:reservation, :morning, room: @other_room, user: @user)
    afternoon = create(:reservation, :afternoon, room: @room, user: @user)

    log_in @user
    visit calendar_reservations_path

    # Click on date cell with reservations
    find(".fc-day-top[data-date='#{Time.current.strftime("%Y-%m-%d")}']").click

    within "#modal-view-event-add" do
      assert_text "Reservation Details"
      assert_text Time.current.strftime("%B %-d, %Y")

      # Initially collapsed
      assert_no_text "9:00 AM - 10:00 AM"

      # Expand reservation list
      find(".reservations-list-toggle").click
      wait_for do
        all(".reservation-item").count == 3
      end

      # Verify chronological ordering and format
      within ".reservations-list" do
        reservation_items = all(".reservation-item")
        assert_equal 3, reservation_items.count

        # Morning reservation
        within reservation_items[0] do
          assert_text "9:00 AM - 10:00 AM"
          assert_text @other_room.name
        end

        # Afternoon reservation
        within reservation_items[1] do
          assert_text "2:00 PM - 3:00 PM"
          assert_text @room.name
        end

        # Evening reservation
        within reservation_items[2] do
          assert_text "4:00 PM - 5:00 PM"
          assert_text @room.name
        end
      end

      # close modal
      sleep 1
      find(".cancel-btn").click
    end

    # Filter calendar but modal should still show all reservations
    select @room.name, from: "room-filter"
    find(".fc-day-top[data-date='#{Time.current.strftime("%Y-%m-%d")}']").click

    within ".reservations-list" do
      assert_text @other_room.name
      assert_text "9:00 AM - 10:00 AM"
      assert_equal 3, all(".reservation-item").count
    end

    # Test collapse functionality
    find(".reservations-list-toggle").click
    assert_no_text "9:00 AM - 10:00 AM"
  end
end

def assert_text_for_date(date, text)
  day_current_header = find(".fc-day-top[data-date='#{date}']")
  day_current_index = day_current_header.find(:xpath, '..').all("td").index(day_current_header)
  events_row = day_current_header.find(:xpath, '../../..').all("tbody tr")[1]
  event_cell = events_row.all("td")[day_current_index]
  assert event_cell.text == text
end

def assert_no_text_for_date(date)
  day_current_header = find(".fc-day-top[data-date='#{date}']")
  day_current_index = day_current_header.find(:xpath, '..').all("td").index(day_current_header)
  events_row = day_current_header.find(:xpath, '../../..').all("tbody tr")[1]
  event_cell = events_row.all("td")[day_current_index]
  assert event_cell.text == ""
end