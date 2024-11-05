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
end
