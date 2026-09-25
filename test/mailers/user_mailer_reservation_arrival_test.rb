require "test_helper"

# Email copy of the access-window push — same words, so the booker can look
# back on what the push said (9/25: a day passer misread the push).
class UserMailerReservationArrivalTest < ActionMailer::TestCase
  setup do
    @room = rooms(:small_meeting_room)
    @room.reservations.delete_all
    @user = users(:cowork_tahoe_member)
  end

  test "unpaid booking: body is the room-only push text" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60, paid: false)
    mail = UserMailer.reservation_arrival_email(res.id)

    assert_equal [@user.email], mail.to
    assert_equal "Your #{@room.name} booking starts at #{res.datetime_in.strftime('%-l:%M %p')}", mail.subject
    body = mail.body.to_s
    assert_includes body, "Please wait until then to use the room, since it may be in use."
    assert_no_match(/You now have access/, body)
  end

  test "paid booking: body includes the building-access line" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60, paid: true)
    body = UserMailer.reservation_arrival_email(res.id).body.to_s
    assert_includes body, "You now have access to #{@room.location.name}."
  end

  test "no mail for a cancelled reservation" do
    res = Reservation.create!(user: @user, room: @room, datetime_in: 50.minutes.from_now, minutes: 60)
    res.update_column(:cancelled, true)
    assert_nil UserMailer.reservation_arrival_email(res.id).message.to
  end
end
