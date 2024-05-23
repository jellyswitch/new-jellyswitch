require "test_helper"

class Billing::Reservations::GrantFreeDayPassTest < ActiveSupport::TestCase
  def setup
    @reservation = reservations(:room_reservation)
    @user = @reservation.user
    @room = @reservation.room

    @location = @room.location
    @free_day_pass_type = day_pass_type(:free_day_pass_type)
    @invoice = invoices(:paid_invoice)
    @interactor = Billing::Reservations::GrantFreeDayPass.new
    @interactor.context.user = @user
    @interactor.context.reservation = @reservation
    @reservation.room = @room
    @room.location = @location
  end

  test "call method grants a free day pass when conditions are met" do
    @room.stubs(:paid_room?).returns(true)
    @user.stubs(:should_charge_for_reservation?).returns(true)
    Invoice.stubs(:find_by).returns(@invoice)

    Rails.logger.expects(:info).with("Granted a free day pass to #{@user.email} for reservation #{@reservation.id}")

    @interactor.call

    new_pass_pass = DayPass.last

    assert_equal new_pass_pass.user, @user
    assert_equal new_pass_pass.day, @reservation.datetime_in.to_date
    assert_equal new_pass_pass.day_pass_type, @free_day_pass_type
    assert_equal new_pass_pass.operator, @location.operator
    assert_equal new_pass_pass.billable_type, "User"
    assert_equal new_pass_pass.billable_id, @user.id
    assert_equal new_pass_pass.invoice, @invoice
  end

  test "call method does not grant a free day pass when conditions are not met" do
    @room.stubs(:paid_room?).returns(false)
    @user.stubs(:should_charge_for_reservation?).returns(false)

    DayPass.expects(:new).never
    Rails.logger.expects(:info).never

    @interactor.call
  end
end
