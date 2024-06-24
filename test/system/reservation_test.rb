require "application_system_test_case"

class ReservationTest < ApplicationSystemTestCase
  setup do
    StripeMock.start

    @room = rooms(:small_meeting_room)
    @user = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @operator.update(credits_enabled: false)
    @reservation = reservations(:future_room_reservation)

    setup_stripe
  end

  teardown do
    StripeMock.stop
  end

  def assert_choose_duration_step()
    assert_text("How long?")

    assert_text(@room.name)
    assert_text(@user.name)
    assert_text(@day)
    assert_text(@hour)
  end

  def assert_confirmation_step()
    assert_text("Confirm reservation")

    assert_choose_duration_step()
    assert_text(@duration)
  end

  def assert_complete_reservation_information()
    assert_text("Reservation Details")

    assert_link(@room.name, href: room_path(@room))
    assert_link(@user.name, href: user_path(@user))

    assert_text("#{@day} at #{@hour}")
    assert_text(@duration)
  end

  test "admin reserve a room for a member" do
    @admin = users(:cowork_tahoe_admin)
    @day = Time.zone.today.strftime("%m/%d/%Y")
    @hour = Time.current.beginning_of_half_hour.strftime("%l:%M%P").strip

    log_in(@admin)

    within "nav" do
      find("button.navbar-toggler").click
      click_on "Rooms & Reservations"
    end

    within ".room-card[data-id='#{@room.id}']" do
      click_on "Reserve Now"
    end

    # Choose member for reservation step
    assert_text(@room.name)
    select @user.name, from: "user_id"
    click_on "Next"

    assert_choose_duration_step()

    click_on "2 hours"
    @duration = "120 minutes"

    assert_confirmation_step()

    click_on "Confirm Reservation"

    assert_complete_reservation_information()
  end

  test "normal user cancel a free room reservation successfully" do
    @user = users(:cowork_tahoe_member)
    log_in @user
    Reservation.any_instance.stubs(:is_charged?).returns(false)

    sleep 1
    visit reservation_path(@reservation)

    click_on "Cancel this reservation"
    assert_text("Are you sure you want to cancel your reservation for #{@room.name}?")
    click_on "Confirm"

    assert_text("Reservation cancelled.")
  end

  test "normal user can not cancel a paid room reservation successfully" do
    @user = users(:cowork_tahoe_member)
    log_in @user

    Reservation.any_instance.stubs(:is_charged?).returns(true)

    @room.update(hourly_rate_in_cents: 1000)

    sleep 1
    visit reservation_path(@reservation)

    assert_text("Note: If you want to cancel this paid reservation room, please contact our workspace admin for assistance.")
    assert_selector "button[data-target='#cancel-reservation-modal'][disabled]", visible: true
  end

  test "charging user for extra hours in the reservation when they book the reservation at first without membership" do
    # Setup
    @user = users(:cowork_tahoe_member)
    log_in @user
    @room.update(hourly_rate_in_cents: 5000)

    invoice = invoices(:paid_invoice)
    invoice.update(billable: @user, amount_due: 5000, created_at: @reservation.created_at + 1.hour)
    stripe_invoice = Stripe::Invoice.create(
      customer: @user.stripe_customer_id,
      currency: "usd",
      amount: 2500,
      number: invoice.number,
      description: "test invoice",
    )

    Invoice.where.not(id: invoice.id).destroy_all # Remove other invoices
    Invoice.any_instance.stubs(:description).returns(@reservation.charge_description)
    Stripe::Invoice.any_instance.stubs(:number).returns(invoice.number)

    sleep 1
    # Test
    visit reservation_path(@reservation)

    assert_text "30 minutes"

    click_on "Extend booking time"
    select "1 hour", from: "extension-duration"

    assert_text "$50.00"
    click_on "Pay & Confirm"

    assert_equal find(".alert-info").text, "Reservation extended successfully."
    assert_text "90 minutes"
  end

  test "not charging user for extra hours in the reservation when they do not have to pay at the beginning" do
    # Setup
    @user = users(:cowork_tahoe_member)
    log_in @user
    @room.update(hourly_rate_in_cents: 5000)

    Invoice.destroy_all # Remove all invoices

    sleep 1
    # Test
    visit reservation_path(@reservation)

    assert_text "30 minutes"

    click_on "Extend booking time"
    select "2 hours", from: "extension-duration"

    assert_text "Free"
    click_on "Pay & Confirm"

    assert_equal find(".alert-info").text, "Reservation extended successfully."
    assert_text "150 minutes"
  end
end
