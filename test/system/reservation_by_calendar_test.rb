require "application_system_test_case"

class ReservationByCalendarTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:small_meeting_room)
    @day = Time.now

    @time = "10:00"

    @duration = "1.5 hours"
    @duration_minutes = 90

    operator = operators(:cowork_tahoe)
    operator.update(credits_enabled: false)

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

    find(".amenity-item", text: "AV - $50").click
    assert_equal "$50.00", find(".price-value").text

    click_on "Confirm"
    wait_for_ajax

    assert_text("Reservation Details")
    assert_link(@room.name, href: room_path(@room))
    assert_link(@user.name, href: user_path(@user))

    assert_text("#{@day.strftime("%m/%d/%Y")} at #{@time}pm")
    assert_text("#{@duration_minutes} minutes")
    assert_text("Amenities: AV")
  end
end
