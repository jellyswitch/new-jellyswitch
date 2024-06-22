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

  # Remove this flow as it is not used in the application
  # test 'member reserve a room' do
  #   @day = Time.zone.today.strftime("%m/%d/%Y")
  #   @hour = Time.current.beginning_of_half_hour.strftime("%l:%M%P").strip
  #   setup_stripe

  #   log_in(@user)
  #   within 'nav' do
  #     click_on 'Reserve a room'
  #   end

  #   within ".room-card[data-id='#{@room.id}']" do
  #     click_on 'Reserve Now'
  #   end

  #   assert_choose_duration_step()

  #   click_on '2 hours'
  #   @duration = '120 minutes'

  #   assert_confirmation_step()

  #   click_on 'Confirm Reservation'

  #   assert_complete_reservation_information()
  # end

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

    @room.update(hourly_rate_in_cents: 1000)

    sleep 1
    visit reservation_path(@reservation)

    assert_text("Note: If you want to cancel this paid reservation room, please contact our workspace admin for assistance.")
    assert_selector "button[data-target='#cancel-reservation-modal'][disabled]", visible: true
  end
end
