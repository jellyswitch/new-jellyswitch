require "application_system_test_case"

class ReservationByCalendarDifferentLocationTest < ApplicationSystemTestCase
  setup do
    @room = rooms(:small_meeting_room)
    @day = Time.now

    @time = "10:00"

    @duration = "1.5 hours"
    @duration_minutes = 90

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    location.update(credits_enabled: false)
    @other_location = create(:location, operator: operator, name: "Other Location")

    Stripe::Invoice.any_instance.stubs(:number).returns("123456")
  end

  test "users go through the reserve by calendar flow and create reservation successfully at another location" do
    StripeMock.start

    @user = users(:cowork_tahoe_member)

    setup_stripe

    room = @other_location.rooms.create!(name: "Other Room", operator: operators(:cowork_tahoe), visible: true, rentable: true)
    room.amenities.create!(name: "AV", price: 50.0, membership_price: 25.5)
    switch_to_location(@other_location)
    log_in @user

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

    select room.name, from: "room_id"

    assert_text "Additional Amenities"

    sleep 2
    find(".amenity-item", text: "AV - $25.5").click
    assert_equal "$25.50", find(".price-value").text

    click_on "Confirm"
    wait_for_ajax

    assert_text("Reservation Details")
    assert_link(room.name, href: room_path(room))
    assert_link(@user.name, href: user_path(@user))

    assert_text("#{@day.strftime("%m/%d/%Y")} at #{@time}pm")
    assert_text("#{@duration_minutes} minutes")
    assert_text("Amenities: AV")
  end

  test "non-membership users reserve paid meeting room at another location" do
    StripeMock.start
    @user = users(:cowork_tahoe_non_member)

    room = @other_location.rooms.create!(name: "Other Room", hourly_rate_in_cents: 1000, operator: operators(:cowork_tahoe), visible: true, rentable: true)
    room.amenities.create!(name: "AV", price: 50.0, membership_price: 25.5)
    room.amenities.create!(name: "Coffee", price: 10.5, membership_price: 0)
    switch_to_location(@other_location)
    log_in @user

    click_on "Book a meeting room"

    assert_text "Reservation Date"

    find(".fc-day-top[data-date='#{@day.strftime("%Y-%m-%d")}']").click
    find(".time-slot", text: @time).click
    find(".duration-slot", text: @duration).click
    select room.name, from: "room_id"

    within ".amenities-list" do
      assert_text("AV - $50")
      assert_text("Coffee - $10.5")
    end

    click_on "Confirm"

    assert_text("Reservation Details")
    assert_text("Payment Required: Yes")
  end
end