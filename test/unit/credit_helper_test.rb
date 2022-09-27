require "test_helper"

class CreditHelperTest < ActionView::TestCase

  test "should subtract credits from user and round down" do
    @room = rooms(:small_meeting_room)
    @reservation = reservations(:room_reservation)
    @duration = @reservation.minutes
    @user = users(:cowork_tahoe_member) # User has 10 credits

    @new_balance = ending_balance(@user, reservation_cost(@room, @duration))
    @user.update(credit_balance: @new_balance)

    assert_equal 7, @user.credit_balance
  end
end