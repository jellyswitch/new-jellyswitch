require 'test_helper'

class SendNotificationsJobTest < ActiveJob::TestCase
  def setup
    @notifiable = reservations(:room_reservation)
    @notifiable_type = 'PaidRoomReservation'
    @notifiable_instance = mock('notifiable_instance')
  end

  test "perform calls NotifiableFactory with correct arguments" do
    NotifiableFactory.expects(:for).with(@notifiable, @notifiable_type).returns(@notifiable_instance)
    @notifiable_instance.expects(:notify)

    SendNotificationsJob.perform_now(@notifiable, @notifiable_type)
  end
end
